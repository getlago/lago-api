# frozen_string_literal: true

module CopyToProduction
  # A user of a sandbox copies one item, with the items it references, into the sandbox's production. Items are
  # matched by code, and production is never changed other than by adding items.
  class CopyService < BaseService
    # An item of the answer: the production record created, or the sandbox parent that is not live yet.
    Entry = Data.define(:item_type, :record)

    Step = Data.define(:item, :source, :existing) do
      def key = [item.item_type, source.id]

      def entry(record = source) = Entry.new(item_type: item.item_type, record:)
    end

    Plan = Data.define(:requested, :copied, :reused, :missing_parent)

    Result = BaseResult[:item, :missing_parent]

    def initialize(organization:, user:, item_type:, id:)
      @organization = organization
      @user = user
      @item_type = item_type.to_s
      @id = id
      super
    end

    def call
      if !organization.sandbox? || !production
        return result.forbidden_failure!(code: "copy_to_production_sandbox_only")
      end
      return result.not_found_failure!(resource: item_type) unless source_record

      # The create services log and track after the commit, attributed to the user's production membership.
      CurrentContext.set(membership_id: production_membership&.id) do
        ActiveRecord::Base.transaction do
          # Membership and activation writes lock production too, so the checks below read their committed state.
          Organizations::SandboxLockService.call!(organization: production)

          check_access
          plan = build_plan
          check_plan(plan)
          copy(plan)
        end
      end

      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e.result.error)
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

    # Members are mirrored from production, so the admin check reads the production membership.
    def production_membership
      production.memberships.active.find_by(user_id: user.id)
    end

    def check_access
      if production.awaiting_payment_method?
        result.forbidden_failure!(code: "organization_inactive").raise_if_error!
      elsif !production_membership&.admin?
        result.forbidden_failure!(code: "copy_to_production_admin_only").raise_if_error!
      end
    end

    # The requested item live, then an item to copy that cannot be, then a parent that is not live. What a create service
    # refuses is known by copying.
    def check_plan(plan)
      if plan.requested.existing
        result.single_validation_failure!(field: :code, error_code: "value_already_exist").raise_if_error!
      end

      plan.copied.each do |step|
        code = step.item.refusal(step.source)
        result.forbidden_failure!(code:).raise_if_error! if code
      end

      return unless plan.missing_parent

      result.missing_parent = plan.missing_parent.entry
      result.forbidden_failure!(code: "copy_to_production_parent_missing").raise_if_error!
    end

    # Dependencies come before the items that reference them, the requested item last. Each one is reused when production
    # has its code: it is neither copied nor visited further, and nothing is visited when the requested item is live.
    def build_plan
      requested = Step.new(item:, source: source_record, existing: item.find_existing(source_record))
      return Plan.new(requested:, copied: [], reused: [], missing_parent: nil) if requested.existing

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
      Plan.new(requested:, copied:, reused:, missing_parent:)
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

    # Creates each item to copy in plan order through its create service, which raises BaseService::FailedResult on a
    # refusal, so that the transaction rolls every copy back.
    def copy(plan)
      resolved = plan.reused.to_h { [it.key, it.existing] }

      plan.copied.each do |step|
        record = step.item.copy!(step.source, resolved)
        resolved[step.key] = record

        Utils::ActivityLog.produce_after_commit(record, step.item.activity_type) if step.item.activity_type
        result.item = step.entry(record) if step.key == plan.requested.key
      end
    end

    def build_item(type)
      Items.build(type, sandbox: organization, production:)
    end
  end
end
