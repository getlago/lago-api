# frozen_string_literal: true

module Types
  module Roles
    class CreateInput < BaseInputObject
      description "Create Role input arguments"

      argument :code, String, required: true
      argument :description, String, required: false
      argument :name, String, required: true
      argument :permissions, [String], required: true
    end
  end
end
