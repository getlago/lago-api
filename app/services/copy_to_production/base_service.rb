# frozen_string_literal: true

module CopyToProduction
  # Shared flow of Copy to production: a user of a sandbox copies one item, with the items it references, into the
  # sandbox's production. Items are matched by code, and production is never changed other than by adding items.
  class BaseService < ::BaseService
    # An item of the answer: a sandbox record to copy, or the production record reused or created.
    Entry = Data.define(:item_type, :record)

    Step = Data.define(:item, :source, :existing) do
      def key = [item.item_type, source.id]

      def entry(record = source) = Entry.new(item_type: item.item_type, record:)
    end

    Plan = Data.define(:copied, :reused, :existing, :missing_parent)

    def initialize(organization:, user:, item_type:, id:)
      @organization = organization
      @user = user
      @item_type = item_type.to_s
      @id = id
      super
    end

    private

    attr_reader :organization, :user, :item_type, :id

    def production
      @production ||= organization.production_organization
    end

    def item
      @item ||= build_item(item_type)
    end

    def source_record
      @source_record ||= item.find_source(id)
    end

    # Refuses an organization that is not a sandbox, and a source the sandbox does not have.
    def check_entry
      return result.forbidden_failure!(code: "copy_to_production_sandbox_only") unless organization.sandbox? && production

      result.not_found_failure!(resource: item_type) unless source_record
    end

    # The error code that refuses the copy in production, or nil.
    def blocking_reason(plan)
      return "organization_inactive" if production.awaiting_payment_method?
      return "copy_to_production_admin_only" unless production_membership&.admin?
      return "copy_to_production_parent_missing" if plan.missing_parent

      "value_already_exist" if plan.existing
    end

    # Members are mirrored from production, so the admin check reads the production membership.
    def production_membership
      @production_membership ||= production.memberships.active.find_by(user_id: user.id)
    end

    # Dependencies come before the items that reference them, the requested item last. Each one is reused when production
    # has its code: it is neither copied nor visited further.
    def build_plan
      copied = []
      reused = []
      missing_parent = nil

      parent_type, parent_source = item.parent(source_record)
      if parent_source
        parent = Step.new(item: build_item(parent_type), source: parent_source, existing: nil)
        existing = parent.item.find_existing(parent_source)
        existing ? reused << parent.with(existing:) : missing_parent = parent
      end

      visit_dependencies(item, source_record, copied, reused, Set.new)
      copied << Step.new(item:, source: source_record, existing: nil)

      Plan.new(copied:, reused:, existing: item.find_existing(source_record), missing_parent:)
    end

    def visit_dependencies(dependent, dependent_source, copied, reused, seen)
      dependent.dependencies(dependent_source).each do |dependency_type, dependency_source|
        step = Step.new(item: build_item(dependency_type), source: dependency_source, existing: nil)
        next unless seen.add?(step.key)

        existing = step.item.find_existing(dependency_source)
        if existing
          reused << step.with(existing:)
        else
          visit_dependencies(step.item, dependency_source, copied, reused, seen)
          copied << step
        end
      end
    end

    def build_item(type)
      Items.build(type, sandbox: organization, production:)
    end
  end
end
