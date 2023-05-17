# frozen_string_literal: true

module V1
  class MembershipSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        user_id: model.user_id,
        organization_id: model.organization_id,
        role: model.role,
      }
    end
  end
end
