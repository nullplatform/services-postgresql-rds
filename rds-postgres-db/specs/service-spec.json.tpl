{
  "name": "RDS PostgreSQL DB",
  "slug": "rds-postgres-db",
  "type": "dependency",
  "unique": false,
  "assignable_to": "any",
  "use_default_actions": true,
  "available_links": ["connect"],
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
        "hostname": {
          "type": "string",
          "title": "Hostname",
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "RDS endpoint hostname",
          "order": 1
        },
        "port": {
          "type": "number",
          "title": "Port",
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "RDS port",
          "order": 2
        },
        "username": {
          "type": "string",
          "title": "DB Username",
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "Database username",
          "order": 3
        },
        "password": {
          "type": "string",
          "title": "DB Password",
          "visibleOn": [],
          "editableOn": [],
          "description": "Database password (internal use — exposed to apps via link)",
          "order": 4
        },
        "database_name": {
          "type": "string",
          "title": "Database",
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "Database name",
          "order": 5
        },
        "master_secret_arn": {
          "type": "string",
          "visibleOn": [],
          "editableOn": [],
          "description": "ARN of the Secrets Manager secret for master credentials (internal use)",
          "order": 6
        }
      }
    },
    "values": {}
  }
}
