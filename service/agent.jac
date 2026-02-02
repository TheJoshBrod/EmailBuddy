include service.nodes;
include service.tools;
include service.prompts;
include service.rag;
import re;

def extract_text(html_content: str) -> str {
    clean_text = re.sub('<[^<]+?>', '', html_content);
    return clean_text.strip();
}



walker: pub EmailBuddyAgent {
    has query: str;
    has chat_history: list[dict] = [];
    has conversation_history: list[dict] = [];

    can start_search with `root entry {

        # Initialize history
        self.conversation_history.append({"role": "system_prompt", "content": sys_prompt});
        
        # Add previous chat history
        for item in self.chat_history {
            role = "user" if item["sender"] == "User" else "assistant";
            content = extract_text(item["message"]);
            self.conversation_history.append({"role": role, "content": content});
        }
        
        clean_query = extract_text(self.query);
        self.conversation_history.append({"role": "user", "content": clean_query});
        
        # Initial search
        self.handle_initial_search(clean_query);
    }

    def handle_initial_search(query: str) -> None {
        try {

            
            # 1. Semantic Search to find entry points
            starting_emails = find_emails(query);
            uuids = [email[0] for email in starting_emails];
            
            # 2. Locate nodes in graph
            finder = FindEmailNode(targets=uuids);
            root spawn finder;
            initial_emails = finder.emails;
            

            initial_emails_formatted = [email_node_to_string(email) for email in initial_emails];

            # 3. Decide next step
            self.conversation_history.append({
                "type": "found-emails", 
                "content": summarize(initial_emails_formatted, self.conversation_history)
            });

            response = choose_initial_email_node(str(initial_emails_formatted), self.conversation_history);


            self.conversation_history.append({
                "type": "agent-choice",
                "content": f"Based on the found emails, I will proceed with option '{response.option}'. My selection is '{response.selection}' because: {response.explanation}"
            });

            # 4. Act on decision
            if response.option == "@end@" {
                 report {"response": respond_to_user(response.selection, self.conversation_history), "source": []};
            }
            elif response.option == "@selected@" {
                target_node = self.find_email_by_uuid(initial_emails, response.selection, self.conversation_history);
                if target_node {
                    visit target_node;
                } else {
                    report {"response": "Error: Could not find the selected email node.", "source": []};
                }
            }
            elif response.option == "@query@" {
                # Recursive query call
                self.handle_initial_search(response.selection);
            }
            else {
                 report {"response": "Error: Invalid agent option returned.", "source": []};
            }

        } except Exception as e {
            print(f"CRITICAL ERROR in Agent: {e}");
            import traceback; 
            traceback.print_exc();
            report {"response": f"Internal Agent Error: {e}", "source": []};
        }
    }

    def find_email_by_uuid(emails: list[EmailNode], target_uuid: str, history: list) -> EmailNode {
        # First pass exact match
        for email in emails {
            if email.email_uuid == target_uuid { return email; }
        }
        
        # Retry logic

        retry_count = 0;
        current_uuid = target_uuid;
        
        while retry_count < 3 {
             history.append({"type": "meta-error", "content": "Email UUID did not match. Retrying."});
             response = retry_extract_identifier(history);

             
             for email in emails {
                if email.email_uuid == response.selection { return email; }
             }
             retry_count += 1;
        }
        return None;
    }

    # Ability to handle Email Node visits
    can investigate_email with EmailNode entry {
        try {

            
            sender = [here <-- (`?Person)];
            recipients = [here --> (`?Person)];
            search_pool = sender + recipients;
            
            sender_fmt = [person_node_to_string(p) for p in sender];
            recipient_fmt = [person_node_to_string(p) for p in recipients];
            email_fmt = email_node_to_string(here);
            
            self.conversation_history.append({
                "type": "found-people-at-email", 
                "content": f"At email {email_fmt}. Found sender: {str(sender_fmt)} and recipients: {str(recipient_fmt)}."
            });
            
            response = choose_next_person_node(str(sender_fmt), str(recipient_fmt), email_fmt, self.conversation_history);


            self.conversation_history.append({
                "type": "agent-choice", 
                "content": f"I am acting on '{response.option}'. I picked '{response.selection}' because: {response.explanation}"
            });

            if response.option == "@end@" {
                report {"response": generate_answer(response.selection, self.conversation_history), "source": []};
            }
            elif response.option == "@selected@" {
                # Find person by email string
                target_person: Person = None;
                for person in search_pool {
                    if person.email == response.selection {
                        target_person = person;
                        break;
                    }
                }
                
                # Simple retry if not found
                if not target_person {
                     # Could add loop here similar to uuid retry if needed

                }

                if target_person {
                    visit target_person;
                } else {
                    report {"response": "Error: Selected person not found.", "source": []};
                }
            }
            elif response.option == "@query@" {
                self.handle_initial_search(response.selection);
            }

        } except Exception as e {
            print(f"Error visiting email node: {e}");
            report {"response": f"Error visiting email: {e}", "source": []};
        }
    }

    # Ability to handle Person Node visits
    can investigate_person with Person entry {
         try {

            
            sent = [here --> (`?EmailNode)];
            received = [here <-- (`?EmailNode)];
            search_pool = sent + received;
            
            sent_fmt = [email_node_to_string(e) for e in sent];
            recv_fmt = [email_node_to_string(e) for e in received];
            person_fmt = person_node_to_string(here);
            
            self.conversation_history.append({
                "type": "found-emails-for-person",
                "content": f"At person {person_fmt}. Found sent emails: {str(sent_fmt)} and received emails: {str(recv_fmt)}."
            });
            
            response = choose_next_email_node(person_fmt, str(sent_fmt), str(recv_fmt), self.conversation_history);

            
            if response.option == "@end@" {
                 report {"response": respond_to_user(response.selection, self.conversation_history), "source": []};
            }
            elif response.option == "@selected@" {
                target_node = self.find_email_by_uuid(search_pool, response.selection, self.conversation_history);
                 if target_node {
                    visit target_node;
                } else {
                    report {"response": "Error: Could not find the selected email node from person.", "source": []};
                }
            }
            elif response.option == "@query@" {
                self.handle_initial_search(response.selection);
            }

         } except Exception as e {
             print(f"Error visiting person node: {e}");
             report {"response": f"Error visiting person: {e}", "source": []};
         }
    }
}
