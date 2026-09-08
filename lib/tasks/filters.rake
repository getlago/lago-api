# frozen_string_literal: true

namespace :filters do
  desc "Clean duplicated filters"
  task deduplicate: :environment do
    charges = Charge.joins(:filters).includes(filters: {values: :billable_metric_filter}).distinct

    charges.find_each do |charge|
      next if charge.filters.count <= 1

      charge.filters.each do |filter|
        h = filter.to_h
        next if filter.reload.deleted_at.present?

        duplicates = charge.filters.select do |f|
          next false if f.id == filter.id
          next false if f.reload.deleted_at.present?

          h.keys.sort == f.to_h.keys.sort && h.keys.all? { |k| h[k].sort == f.to_h[k].sort }
        end

        duplicates.each { |f| f.discard! }
      end
    end
  end

  # A plan's own filters with no code, on charges that have overrides. Editing one enqueues an
  # update the cascade cannot address — the code is what identifies the copy on the override — so
  # the job dies on MissingParentCode.
  #
  # This lists more than can fail today: `ChargeFilters::CascadeService#child_ids` only reaches an
  # override whose plan carries an active or pending subscription, and the EXISTS below does not
  # check that. Deliberately so — an override without one starts mattering the day it gains one.
  #
  # Filters on the overrides themselves are not listed: nothing dispatches a job for them, so a
  # missing code there costs nothing.
  desc "Report the plan filters with no code to cascade with"
  task report_parent_codes: :environment do
    scope = ChargeFilter.unscope(:order)
      .where(code: nil, deleted_at: nil)
      .joins(charge: :plan)
      .where(charges: {parent_id: nil, deleted_at: nil}, plans: {parent_id: nil, deleted_at: nil})
      .where("EXISTS (SELECT 1 FROM charges children WHERE children.parent_id = charge_filters.charge_id AND children.deleted_at IS NULL)")

    puts "##################################"
    puts "Plan filters with no code, on charges that have overrides: #{scope.count}"
    puts ""

    by_organization = scope.group(:organization_id).count
    if by_organization.any?
      puts "By organization:"
      Organization.where(id: by_organization.keys).order(:name).each do |organization|
        puts "- #{organization.name}: #{by_organization[organization.id]} filters"
      end

      puts ""
      puts "The charges to look at first:"
      scope.group(:charge_id).order(Arel.sql("count(*) DESC")).limit(25).count.each do |charge_id, filters|
        puts "- charge #{charge_id}: #{filters} filters"
      end
    end
  end

  # Charge filters the backfill deliberately left alone. Two situations produce them, and neither
  # is a failure:
  #
  #   - two filters on one charge hold the same values, because removing a value from a billable
  #     metric trimmed them onto the same predicate. Whichever kept the code would be the one that
  #     bills from then on, and that is not a migration's call.
  #
  #   - an override kept a filter its plan no longer has. There is nothing left to link it to —
  #     the plan's filter is gone, or the parent charge was deleted and `dependent: :nullify` cut
  #     the link. This is damage already done and no backfill undoes it.
  #
  # Cleaning up the first kind and running upgrade:perform_required_jobs again converges.
  desc "Report the charge filters left without a code"
  task report_codes: :environment do
    # `unscope(:order)`, because the model orders by `updated_at` by default and `order` adds to
    # that rather than replacing it. Grouping by `charge_id` then leaves `updated_at` outside the
    # GROUP BY, which Postgres rejects.
    scope = ChargeFilter.unscope(:order).where(code: nil, deleted_at: nil)

    puts "##################################"
    puts "Charge filters without a code: #{scope.count}"
    puts ""
    puts "They are either two filters sharing one predicate on the same charge — where picking"
    puts "which keeps the code would decide which one bills — or an override holding a filter its"
    puts "plan no longer has, which has nothing left to link to."
    puts ""
    puts "The charges to look at first:"

    scope.group(:charge_id).order(Arel.sql("count(*) DESC")).limit(25).count.each do |charge_id, filters|
      pp "- charge #{charge_id}: #{filters} filters"
    end
  end
end
