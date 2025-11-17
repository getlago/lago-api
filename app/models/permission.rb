# frozen_string_literal: true

class Permission
  UNRELEASED_PERMISSIONS = %w[
    payment_methods:view
    payment_methods:create
    payment_methods:update
    payment_methods:delete
  ]

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

  DEFAULT_ROLE_TABLE = Permission::ADMIN_PERMISSIONS_HASH.filter_map do |permission_name, admin_value|
    next if UNRELEASED_PERMISSIONS.include?(permission_name)
    [
      permission_name,
      {
        "admin" => admin_value,
        "manager" => Permission::MANAGER_PERMISSIONS_HASH[permission_name],
        "finance" => Permission::FINANCE_PERMISSIONS_HASH[permission_name]
      }
    ]
  end.to_h.freeze
  # rubocop:enable Layout/ClassStructure
end
