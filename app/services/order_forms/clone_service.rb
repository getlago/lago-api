# frozen_string_literal: true

module OrderForms
  class CloneService < BaseService
    attr_reader :order_form

    def initialize(order_form:)
      @order_form = order_form
      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "order_form") unless order_form
      return result.validation_failure!(errors: {order_form: ["cloning_disallowed"]}) unless clonable?(order_form:)

      result.order_form = clone(order_form:)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def clonable?(order_form:)
      return false if order_form.signed? || order_form.executed?
      return false if order_form.organization.order_forms.where(
        sequential_id: order_form.sequential_id,
        version: (order_form.version + 1)..
      ).exists?

      true
    end

    def clone(order_form:)
      OrderForm.transaction do
        cloned_order_form = copy_order_form(order_form:)
        copy_catalog_references(order_form:, cloned_order_form:)
        void!(order_form:)

        return cloned_order_form
      end
    end

    def copy_order_form(order_form:)
      cloned_order_form = order_form.dup
      cloned_order_form.update!(
        status: :draft,
        version: order_form.version + 1
      )

      cloned_order_form
    end

    def copy_catalog_references(order_form:, cloned_order_form:)
      order_form.catalog_references.each do |ref|
        cloned_order_form.catalog_references.create!(
          organization: ref.organization,
          referenced_type: ref.referenced_type,
          referenced_id: ref.referenced_id
        )
      end
    end

    def void!(order_form:)
      return if order_form.voided?

      order_form.update!(
        void_reason: :superseded,
        status: :voided
      )
    end
  end
end
