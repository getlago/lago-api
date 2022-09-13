# frozen_string_literal: true

module Plans
  class DestroyService < BaseService
    def destroy(id)
      plan = result.user.plans.find_by(id: id)
      return result.not_found_failure!(resource: 'plan') unless plan

      unless plan.deletable?
        return result.fail!(
          code: 'forbidden',
          message: 'Plan is attached to active subscriptions',
        )
      end

      plan.destroy!

      result.plan = plan
      result
    end

    def destroy_from_api(organization:, code:)
      plan = organization.plans.find_by(code: code)
      return result.not_found_failure!(resource: 'plan') unless plan

      unless plan.deletable?
        return result.fail!(
          code: 'forbidden',
          message: 'plan is attached to an active subscriptions',
        )
      end

      plan.destroy!

      result.plan = plan
      result
    end
  end
end
