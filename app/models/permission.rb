# frozen_string_literal: true

class Permission
  def self.yaml_to_hash(filename)
    YAML.parse_file(Rails.root.join('app/config/permissions', filename)).to_ruby.to_dotted_hash(separator: ':')
  end

  # rubocop:disable Layout/ClassStructure
  DEFAULT_PERMISSIONS_HASH = yaml_to_hash('definition.yml').freeze

  ADMIN_PERMISSIONS_HASH = DEFAULT_PERMISSIONS_HASH.transform_values { true }.freeze

  MANAGER_PERMISSIONS_HASH = yaml_to_hash('role-manager.yml').freeze

  FINANCE_PERMISSIONS_HASH = yaml_to_hash('role-finance.yml').freeze
  # rubocop:enable Layout/ClassStructure
end
