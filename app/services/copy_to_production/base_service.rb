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

    Plan = Data.define(:requested, :copied, :reused, :existing, :missing_parent)

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
      if !organization.sandbox? || !production
        result.forbidden_failure!(code: "copy_to_production_sandbox_only")
      elsif !source_record
        result.not_found_failure!(resource: item_type)
      end
    end

    # The error code that refuses the user access to production, or nil. Checked before the plan, which reads
    # production records.
    def access_refusal
      if production.awaiting_payment_method?
        "organization_inactive"
      elsif !production_membership&.admin?
        "copy_to_production_admin_only"
      end
    end

    # The copy's own refusal, as [error code, refused step], or nil: the requested item live, then an item to copy that
    # cannot be, then a parent that is not live. What a create service refuses is known by copying.
    def plan_refusal(plan)
      return ["value_already_exist", plan.requested] if plan.existing

      plan.copied.each do |step|
        code = step.item.refusal(step.source)
        return [code, step] if code
      end

      ["copy_to_production_parent_missing", nil] if plan.missing_parent
    end

    # Members are mirrored from production, so the admin check reads the production membership.
    def production_membership
      production.memberships.active.find_by(user_id: user.id)
    end

    # Dependencies come before the items that reference them, the requested item last. Each one is reused when production
    # has its code: it is neither copied nor visited further, and nothing is visited when the requested item is live.
    def build_plan
      requested = Step.new(item:, source: source_record, existing: item.find_existing(source_record))
      return Plan.new(requested:, copied: [], reused: [], existing: moved.existing, missing_parent: nil) if requested.existing

      copied = []
      reused = []
      missing_parent = nil

      parent_type, parent_source = item.parent(source_record)
      if parent_source
        parent = Step.new(item: build_item(parent_type), source: parent_source, existing: nil)
        existing = parent.item.find_existing(parent_source)
        existing ? reused << parent.with(existing:) : missing_parent = parent
      end

      visit(requested, copied, reused, Set.new)
      Plan.new(requested:, copied:, reused:, existing: nil, missing_parent:)
    end

    def visit(step, copied, reused, seen)
      step.item.dependencies(step.source).each do |dependency_type, dependency_source|
        dependency = Step.new(item: build_item(dependency_type), source: dependency_source, existing: nil)
        next unless seen.add?(dependency.key)

        existing = dependency.item.find_existing(dependency_source)
        existing ? reused << dependency.with(existing:) : visit(dependency, copied, reused, seen)
      end

      copied << step
    end

    # Creates each item to copy in plan order, yielding each step with its production record. A create service that
    # refuses raises BaseService::FailedResult, so that the caller's transaction rolls every copy back.
    def copy(plan)
      resolved = plan.reused.to_h { [it.key, it.existing] }

      plan.copied.each do |step|
        resolved[step.key] = step.item.copy!(step.source, resolved)
        yield step, resolved[step.key]
      end
    end

    def build_item(type)
      Items.build(type, sandbox: organization, production:)
    end
  end
end
