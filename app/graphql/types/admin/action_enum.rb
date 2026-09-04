# frozen_string_literal: true

module Types
  module Admin
    class ActionEnum < Types::BaseEnum
      graphql_name "AdminActionEnum"

      value "toggle_on", "Feature was enabled"
      value "toggle_off", "Feature was disabled"
      value "org_created", "Feature set during org creation"
      value "rollback", "Change was rolled back"
    end
  end
end
