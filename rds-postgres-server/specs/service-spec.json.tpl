{
  "name": "RDS PostgreSQL",
  "slug": "rds-postgres",
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
      "required": ["instance_class"],
      "properties": {
        "instance_class": {
          "type": "string",
          "title": "Instance Class",
          "default": "db.t3.micro",
          "enum": ["db.t3.micro", "db.t3.small", "db.t3.medium", "db.m5.large"],
          "description": "RDS instance type (affects CPU and RAM)",
          "editableOn": ["create", "update"],
          "order": 1
        },
        "allocated_storage": {
          "type": "number",
          "title": "Storage (GB)",
          "default": 20,
          "minimum": 20,
          "maximum": 1000,
          "description": "Allocated storage size in GB",
          "editableOn": ["create", "update"],
          "order": 2
        },
        "postgres_version": {
          "type": "string",
          "title": "PostgreSQL Version",
          "default": "16",
          "enum": ["14", "15", "16"],
          "description": "PostgreSQL major version (cannot be changed after creation)",
          "editableOn": ["create"],
          "order": 3
        },
        "hostname": {
          "type": "string",
          "title": "Hostname",
          "export": true,
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "RDS endpoint hostname (auto-populated after creation)",
          "order": 4
        },
        "port": {
          "type": "number",
          "title": "Port",
          "export": true,
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "RDS port (auto-populated after creation)",
          "order": 5
        },
        "db_instance_identifier": {
          "type": "string",
          "export": false,
          "visibleOn": [],
          "editableOn": [],
          "description": "Internal AWS RDS instance identifier"
        },
        "master_secret_arn": {
          "type": "string",
          "export": false,
          "visibleOn": [],
          "editableOn": [],
          "description": "ARN of the Secrets Manager secret holding master credentials (internal use)"
        }
      }
    },
    "values": {}
  }
}
