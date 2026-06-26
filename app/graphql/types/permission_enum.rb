# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  class PermissionEnum < Types::BaseEnum
    description "Permission"

    Permission.permissions_hash.each_key do |permission|
      value permission.tr(":", "_"), value: permission
    end
  end
end
