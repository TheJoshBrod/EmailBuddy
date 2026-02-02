import email;

def parse_email_content(content: str) -> dict {
    # If content looks like our manual specific format, try to parse it specifically
    # Format from create_email_embedding: "date: <...>\nsender: <...>\nrecipient: <...>\nsubject: <...>\n\nbody:<...>"
    data: dict = {};
    
    if content.startswith("date: <") {
        lines = content.split('\n');
        for line in lines {
            if line.startswith("date: <") {
                data["date"] = line.split("date: <")[1].strip(">");
            } elif line.startswith("sender: <") {
                data["from"] = line.split("sender: <")[1].strip(">");
            } elif line.startswith("recipient: <") {
                data["to"] = line.split("recipient: <")[1].strip(">");
            } elif line.startswith("subject: <") {
                data["subject"] = line.split("subject: <")[1].strip(">");
            } elif line.startswith("body:<") {
                data["body"] = line.split("body:<")[1].strip(">");
            }
        }
        return data;
    }

    # Fallback to standard email parsing for raw email text
    msg = email.message_from_string(content, policy=email.policy.default);
    
    body = "";
    if msg.is_multipart() {
        for part in msg.walk() {
            if part.get_content_type() == "text/plain" {
                body = part.get_content();
                break;
            }
        }
    } else {
        body = msg.get_content();
    }

    return {
        "date": msg.get("Date", ""),
        "from": msg.get("From", ""),
        "to": msg.get("To", ""),
        "subject": msg.get("Subject", ""),
        "body": body
    };
}
