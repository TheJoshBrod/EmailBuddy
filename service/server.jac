"""Contains all the API Endpoints."""

# Python Libraries
import json;
import uuid;
import typing;
import sqlite3;

# Jac Files
include service.tools;
include service.nodes;
include service.rag;
include service.parser;
include service.agent;


walker: pub load_graph_from_db {
    can setup with `root entry {
        conn = sqlite3.connect("vectorDB.db");
        cursor = conn.cursor();
        
        # Check if table exists
        try {
            cursor.execute("SELECT content FROM emails");
            rows = cursor.fetchall();
            
            emails_to_restore = [];
            
            for row in rows {
                content = row[0];
                # Use robust parsing
                email_data = parse_email_content(content);
                
                if "from" in email_data {
                    emails_to_restore.append(email_data);
                }
            }
            
            if len(emails_to_restore) > 0 {
                root spawn upload_emails(raw_emails=emails_to_restore, skip_embedding=True);
            }
            
        } except Exception as e {
            print(f"Database empty or error reading: {e}");
        }
        
        conn.close();
    }
}



walker: pub upload_emails{
    has raw_emails: list;
    has skip_embedding: bool = False;

    can upload_email with `root entry{
        for msg in self.raw_emails {

            # Generate uuid for email (useful for retrieval later)
            stable_key: str = f"{msg.get('from','')}-{msg.get('date','')}-{msg.get('subject','')}-{msg.get('body','')}";
            email_uuid = str(uuid.uuid3(uuid.NAMESPACE_DNS, stable_key));

            # -----------------------
            # - HANDLE EMAIL SENDER -
            # -----------------------
            
            # Extract sender info
            sender_raw: str = msg.get("from", "");
            if not sender_raw{
                continue;
            }
            response = normalize(sender_raw);
            name = response[0];
            sender_email = response[1]; 

            # Spawn walker to check if sender node already exists
            FindSend = FindSenderNode(target=sender_email);
            root spawn FindSend;

            # Check if sender (person node) found
            sender = FindSend.person;
            if FindSend.person is not None {
                # If it exists set to existing node
                if sender.name == "" and name != "" {
                    sender.name = name;
                }
            }
            else{
                # else create new node connected to root
                sender = Person(name=name, email=sender_email);
                root ++> sender;            
            }


            # --------------------------
            # - HANDLE EMAIL RECIPIENT -
            # --------------------------

            # Extract recipient information
            recipient_raw = msg.get("to", "");
            if not recipient_raw{
                continue;
            }
            email_list = recipient_raw.split(", ");
            email_list = [normalize(email) for email in email_list];

            # Spawn walker to check if recipient node already exists
            FindRec = FindRecipientNodes(targets=email_list);
            root spawn FindRec;
            found = FindRec.persons;

            # For recipients (person nodes) that don't exit, make them.
            if len(found) != len(email_list) {
                
                missing_emails: list[tuple[str, str]] = FindRec.missing; # list[(name, email_addr), ...]
                for missing in missing_emails {

                    name = missing[0];
                    email = missing[1];

                    recipient = Person(name=name, email=email);
                    root ++> recipient;

                    found.append(recipient);
                }
            }

            # Exported Gmail inboxes don't always provide names, this updates existing email nodes without names 
            name_lookup: dict = {person[1]: person[0] for person in email_list};
            for person_node in found {
                if person_node.name == "" and person_node.email in name_lookup {
                    new_name = name_lookup[person_node.email];
                    if new_name != "" {
                        person_node.name = new_name;
                    }
                }
            }

            # ----------------
            # - HANDLE EMAIL -
            # ----------------

            # Spawn walker to check if email node already exists
            FindEmail = FindEmailNode(targets=[email_uuid]);
            sender spawn FindEmail;
            emails = FindEmail.emails;

            if len(emails) != 0{
                continue;
            }

            # Create new Email node
            email = EmailNode(sender=sender_raw, recipients=recipient_raw, date=msg["date"], subject=msg["subject"], body=msg["body"], email_uuid=email_uuid);
            root ++> email;

            # Link sender to email
            sender ++> email;

            # Link recipients to email
            for person in found {
                email ++> person;
            }

            # Generate embedding for the email content
            if not self.skip_embedding {
                create_email_embedding(msg, email_uuid);
            }
        }
    }
}

walker: pub get_email_count {
    has count: int = 0;

    can start with `root entry {
        emails = [here -->](`?EmailNode);
        report {"count": len(emails)};
    }
}

walker: pub ask_email {
    has query: str;
    has chat_history: list[dict] = [];

    can handle_query with `root entry {
        # Simply spawn the agent
        root spawn EmailBuddyAgent(query=self.query, chat_history=self.chat_history);
    }
}