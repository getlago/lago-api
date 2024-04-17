# frozen_string_literal: true

module Types
  class PermissionsType < Types::BaseObject
    description 'Permissions Type'

    Permission::DEFAULT_PERMISSIONS_HASH.keys.each do |permissions|
      field permissions, Boolean, null: false
    end
  end
end
