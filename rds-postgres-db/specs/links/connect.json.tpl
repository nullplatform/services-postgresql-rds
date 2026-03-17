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
      "required": [],
      "properties": {
        "server_service_id": {
          "type": "string",
          "title": "RDS Server Service ID",
          "description": "ID of the rds-postgres-server service. Auto-discovered from the namespace (override only if multiple exist).",
          "editableOn": [],
          "visibleOn": [],
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
        "hostname": {
          "type": "string",
          "title": "Hostname",
          "export": true,
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "RDS endpoint hostname",
          "order": 3
        },
        "port": {
          "type": "number",
          "title": "Port",
          "export": true,
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "RDS port",
          "order": 4
        },
        "username": {
          "type": "string",
          "title": "DB Username",
          "export": true,
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "Database username (derived from application ID)",
          "order": 5
        },
        "password": {
          "type": "string",
          "title": "DB Password",
          "export": {"type": "environment_variable", "secret": true},
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "Database password (auto-generated)",
          "order": 6
        },
        "database_name": {
          "type": "string",
          "title": "Database",
          "export": true,
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "Database name (derived from application ID)",
          "order": 7
        },
        "master_secret_arn": {
          "type": "string",
          "export": false,
          "visibleOn": [],
          "editableOn": [],
          "description": "ARN of the Secrets Manager secret for master credentials (internal use)"
        }
      }
    },
    "values": {}
  }
}
