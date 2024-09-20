# frozen_string_literal: true

# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require_relative "config/application"
require "graphql/rake_task"

Rails.application.load_tasks

GraphQL::RakeTask.new(
  schema_name: "Schemas::ApiSchema",
  idl_outfile: "graphql_schemas/api.graphql",
  json_outfile: "graphql_schemas/api.json"
)

GraphQL::RakeTask.new(
  schema_name: "Schemas::CustomerPortalSchema",
  idl_outfile: "graphql_schemas/customer_portal.graphql",
  json_outfile: "graphql_schemas/customer_portal.json"
)
