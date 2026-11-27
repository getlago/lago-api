# frozen_string_literal: true

module CopyToProduction
  module Items
    # A plan is copied whole: its rate cards and phases after it, its wallets, entitlements and taxes with it. What they
    # reference is reused by code or copied before it.
    class CatalogPlanItem < BaseItem
      ATTRIBUTES = %i[name code description invoice_display_name currency].freeze
      CREDIT_ALLOCATION_ATTRIBUTES = %i[
        code trigger billing_cycles threshold_amount_cents credit_amount_cents purchase_amount_cents priority
        invoice_requires_successful_payment
      ].freeze

      def dependencies(source)
        dependencies = source.taxes.sort_by(&:code).map { ["tax", it] }
        dependencies += entitlements(source).map { ["feature", it.feature] }

        wallets(source).each do |wallet|
          dependencies += wallet.taxes.sort_by(&:code).map { ["tax", it] }
          dependencies += selectors(wallet).flat_map { target_dependencies(it) }
          dependencies += credit_allocations(wallet).flat_map { target_dependencies(it) }
        end

        dependencies.uniq
      end

      def children(source)
        source.applied_rate_cards.reject { it.rate_card.discarded? }.sort_by { it.rate_card.code }
          .map { ["plan_rate_card", it] }
      end

      # Without selectors a live wallet applies to every fee, while this one reaches nothing. The entitlement service
      # casts a value by the live privilege's type, so a live privilege of another type would grant another value.
      def refusal(source)
        if wallets(source).any? { it.selectors.any? && selectors(it).empty? }
          "copy_to_production_target_deleted"
        elsif entitlements(source).any? { privilege_type_changed?(it) }
          "copy_to_production_privilege_mismatch"
        end
      end

      def copy!(source, resolved)
        plan = CatalogPlans::CreateService.call!(
          {
            **source.slice(*ATTRIBUTES).symbolize_keys,
            organization_id: production.id,
            tax_codes: source.taxes.map(&:code)
          }
        ).catalog_plan

        copy_entitlements!(source, plan)
        wallets(source).each { copy_wallet!(it, plan, resolved) }
        plan
      end

      # Catalog plans are logged as plans.
      def activity_type
        "plan.copied_to_production"
      end

      private

      def entitlements(source)
        source.entitlements.select(&:feature).sort_by { it.feature.code }
      end

      def wallets(source)
        source.wallets.sort_by(&:code)
      end

      # A selector or a credit allocation on a deleted target was left behind by the deletion: it reaches nothing.
      def selectors(wallet)
        wallet.selectors.reject { target_of(it)&.discarded? }
          .sort_by { [it.selector_type, (target_of(it)&.code || it.fee_type).to_s] }
      end

      # An ongoing balance allocation has no target.
      def credit_allocations(wallet)
        wallet.credit_allocations.reject { target_of(it)&.discarded? }.sort_by(&:code)
      end

      def privilege_type_changed?(entitlement)
        live_feature = production.features.find_by(code: entitlement.feature.code)
        live_privileges = live_feature ? live_feature.privileges.index_by(&:code) : {}

        entitlement.values.filter_map(&:privilege).any? do |privilege|
          live_privilege = live_privileges[privilege.code]
          live_privilege && live_privilege.value_type != privilege.value_type
        end
      end

      def target_of(record)
        record.try(:product_category) || record.product || record.product_filter
      end

      def target_dependencies(record)
        if record.try(:product_category)
          [["product_category", record.product_category]]
        elsif record.product
          product_dependencies(record.product)
        elsif record.product_filter
          product_dependencies(record.product_filter.product)
        else
          []
        end
      end

      # Entitlements are created by feature and privilege codes, without the plan.updated event of a plan update.
      def copy_entitlements!(source, plan)
        params = entitlements(source).to_h do |entitlement|
          values = entitlement.values.select(&:privilege).to_h { [it.privilege.code, it.value] }
          [entitlement.feature.code, values]
        end
        if params.any?
          Entitlement::PlanEntitlementsUpdateService.call!(
            organization: production,
            plan:,
            entitlements_params: params,
            partial: false,
            send_webhook: false
          )
        end
      end

      def copy_wallet!(wallet, plan, resolved)
        live_wallet = PlanWallets::CreateService.call!(
          catalog_plan: plan,
          params: wallet.slice(*PlanWallets::CreateService::ATTRIBUTES).symbolize_keys.merge(
            tax_codes: wallet.taxes.map(&:code),
            applies_to: applies_to(wallet),
            metadata: wallet.metadata&.value
          )
        ).plan_wallet

        # Credit allocations have no create service: they are written as Contracts::MaterializeWalletsService does.
        credit_allocations(wallet).each do |allocation|
          live_wallet.credit_allocations.create!(
            organization: production,
            **allocation.slice(*CREDIT_ALLOCATION_ATTRIBUTES).symbolize_keys,
            **live_targets(allocation, resolved)
          )
        end

        wallet.alerts.sort_by(&:code).each { copy_alert!(it, live_wallet) }
      end

      def applies_to(wallet)
        entries = selectors(wallet).map do |selector|
          case selector.selector_type
          when "fee_type"
            {type: "fee_type", code: selector.fee_type}
          when "product_category"
            {type: "product_category", code: selector.product_category.code}
          when "product"
            {type: "product", code: selector.product.code, with_product_filters: selector.with_product_filters}
          when "product_filters"
            {type: "product_filters", code: selector.product_filter.code, product_code: selector.product_filter.product.code}
          end
        end

        {include: entries} if entries.any?
      end

      def live_targets(allocation, resolved)
        if allocation.product
          {product: resolved.fetch(["product", allocation.product_id])}
        elsif (filter = allocation.product_filter)
          live_product = resolved.fetch(["product", filter.product_id])
          {product_filter: live_product.filters.find_by(code: filter.code) || not_found!("product_filter")}
        else
          {}
        end
      end

      def copy_alert!(alert, live_wallet)
        UsageMonitoring::CatalogWalletAlerts::CreateService.call!(
          plan_wallet: live_wallet,
          params: {
            alert_type: alert.alert_type,
            code: alert.code,
            name: alert.name,
            thresholds: alert.thresholds.sort_by(&:value).map { it.slice(:value, :code, :recurring, :notify_on).symbolize_keys }
          }
        )
      end
    end
  end
end
