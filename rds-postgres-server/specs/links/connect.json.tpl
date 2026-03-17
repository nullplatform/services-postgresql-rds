{
  "name": "Connect",
  "slug": "connect",
  "unique": false,
  "assignable_to": "any",
  "use_default_actions": true,
  "selectors": {
    "category": "Database",
    "imported": false,
    "provider": "AWS",
    "sub_category": "Relational Database"
  },
  "attributes": {
    "schema": {
      "type": "object",
      "$schema": "http://json-schema.org/draft-07/schema#",
      "required": ["db_name", "access_level"],
      "properties": {
        "db_name": {
          "type": "string",
          "title": "Database Name",
          "description": "Name of the database to create inside the RDS instance",
          "editableOn": ["create"],
          "order": 1
        },
        "access_level": {
          "enum": ["read", "write", "read-write"],
          "type": "string",
          "title": "Access Level",
          "default": "read-write",
          "editableOn": ["create", "update"],
          "description": "Permission level: read (SELECT), write (INSERT/UPDATE/DELETE), read-write (both)",
          "order": 2
        },
        "username": {
          "type": "string",
          "title": "DB Username",
          "export": true,
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "Database username (auto-populated after link creation)",
          "order": 3
        },
        "password": {
          "type": "string",
          "title": "DB Password",
          "export": {"type": "environment_variable", "secret": true},
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "Database password (auto-populated, delivered as secret env var)",
          "order": 4
        },
        "database_name": {
          "type": "string",
          "title": "Database",
          "export": true,
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "Database name (auto-populated after link creation)",
          "order": 5
        }
      }
    },
    "values": {}
  }
}
