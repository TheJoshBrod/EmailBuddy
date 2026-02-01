"""Main entry point for the Jac client application."""

# Server-side imports
include service.server;

# Initialize root node on server startup
walker: pub init_root {
    can setup with `root entry {
        print("Root node initialized successfully");
    }
}

# This runs when the server starts
with entry {
    root spawn init_root();
    root spawn load_graph_from_db();
    root spawn PrintGraph();
}

# Client-side imports
cl import from react { useEffect }
cl import from .components.EmailBuddyLayout { EmailBuddyLayout }
cl import "./global.css";

# Client-side component
cl {
    def:pub app() -> any {
        


        return (
            <div>
            <div>
                <EmailBuddyLayout />
            </div>
            </div>
        );
    }
}