# frozen_string_literal: true

module CopyToProduction
  module Items
    # A plan is copied whole: its rate cards with their phases after it, its wallets with their scope, credit allocations
    # and alerts, its entitlements and its taxes. The taxes, features, products and categories they reference are
    # reused by code or copied before it.
    class CatalogPlanItem < BaseItem
      ATTRIBUTES = %i[name code description invoice_display_name currency].freeze
      CREDIT_ALLOCATION_ATTRIBUTES = %i[
        code trigger billing_cycles threshold_amount_cents credit_amount_cents purchase_amount_cents priority
        invoice_requires_successful_payment
      ].freeze
      PRODUCT_PRELOADS = [:product_category, *ProductItem::OWN_PRELOADS].freeze
      PRODUCT_TARGET_PRELOADS = [{product: PRODUCT_PRELOADS}, {product_filter: {product: PRODUCT_PRELOADS}}].freeze
      PRELOADS = [
        :taxes,
        {entitlements: [:feature, {values: :privilege}]},
        {applied_rate_cards: [:catalog_plan, *PlanRateCardItem::PRELOADS]},
        {
          wallets: [
            :taxes, :metadata, {alerts: :thresholds}, {credit_allocations: PRODUCT_TARGET_PRELOADS},
            {selectors: [:product_category, *PRODUCT_TARGET_PRELOADS]}
          ]
        }
      ].freeze

      def find_source(id)
        sandbox.catalog_plans.includes(*PRELOADS).find_by(id:)
      end

      def find_existing(source)
        production.catalog_plans.find_by(code: source.code)
      end

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

      # Nothing of a plan whose code is live is copied: its rate cards would be read against the live plan.
      def children(source)
        return [] if find_existing(source)

        source.applied_rate_cards.reject { it.rate_card.discarded? }.sort_by { it.rate_card.code }
          .map { ["plan_rate_card", it] }
      end

      # The entitlements and wallets of a plan name privileges and filters by code, which a reused live feature or
      # product may lack.
      def refusal(source)
        live_features = production.features.includes(:privileges)
          .where(code: entitlements(source).map { it.feature.code }).index_by(&:code)
        return "copy_to_production_privilege_missing" if entitlements(source).any? { missing_privilege?(it, live_features) }

        "copy_to_production_filter_missing" if wallets(source).any? { missing_filter?(it) }
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

      def unique_indexes
        {"index_catalog_plans_on_organization_id_and_code" => :code}
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
        wallet.selectors.reject { (target = target_of(it)) && target.discarded? }
      end

      # An ongoing balance allocation has no target.
      def credit_allocations(wallet)
        wallet.credit_allocations.reject { (target = target_of(it)) && target.discarded? }
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

      def missing_privilege?(entitlement, live_features)
        live_feature = live_features[entitlement.feature.code]
        return false unless live_feature

        (entitlement.values.filter_map { it.privilege&.code } - live_feature.privileges.map(&:code)).any?
      end

      def missing_filter?(wallet)
        (selectors(wallet) + credit_allocations(wallet)).filter_map(&:product_filter).any? do |filter|
          live_filter_codes(filter.product)&.exclude?(filter.code)
        end
      end

      # Entitlements are created by feature and privilege codes, without the plan.updated event of a plan update.
      def copy_entitlements!(source, plan)
        params = entitlements(source).to_h do |entitlement|
          values = entitlement.values.select(&:privilege).to_h { [it.privilege.code, it.value] }
          [entitlement.feature.code, values]
        end
        return if params.empty?

        Entitlement::PlanEntitlementsUpdateService.call!(
          organization: production,
          plan:,
          entitlements_params: params,
          partial: false,
          send_webhook: false
        )
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
        credit_allocations(wallet).sort_by(&:code).each do |allocation|
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
          {product_filter: live_filters(resolved.fetch(["product", filter.product_id])).fetch(filter.code)}
        else
          {}
        end
      end

      def live_filters(live_product)
        @live_filters ||= {}
        @live_filters[live_product.id] ||= live_product.filters.index_by(&:code)
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
