# frozen_string_literal: true

class Permission
  def self.yaml_to_hash(filename)
    h = YAML.parse_file(Rails.root.join("app/config/permissions", filename)).to_ruby
    DottedHash.new(h, separator: ":").transform_values(&:present?)
  end

  # rubocop:disable Layout/ClassStructure
  EMPTY_PERMISSIONS_HASH = {}.freeze

  DEFAULT_PERMISSIONS_HASH = yaml_to_hash("definition.yml").freeze

  ADMIN_PERMISSIONS_HASH = DEFAULT_PERMISSIONS_HASH.transform_values { true }.freeze

  MANAGER_PERMISSIONS_HASH = DEFAULT_PERMISSIONS_HASH.merge(yaml_to_hash("role-manager.yml")).freeze

  FINANCE_PERMISSIONS_HASH = DEFAULT_PERMISSIONS_HASH.merge(yaml_to_hash("role-finance.yml")).freeze
  # rubocop:enable Layout/ClassStructure
end
