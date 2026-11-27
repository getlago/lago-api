# frozen_string_literal: true

# A sandbox catalog plan with a rate card in a categorized product and one in a standalone product, phases, a tax, an
# entitlement and a wallet with its tax, selectors, credit allocation and alert. Needs `sandbox` and `production`.
RSpec.shared_context "with a copy to production catalog plan" do
  let(:plan) do
    create(:catalog_plan, organization: sandbox, code: "pro", name: "Pro", description: "For teams",
      invoice_display_name: "Pro plan", currency: "EUR")
  end
  let(:category) { create(:product_category, organization: sandbox, code: "compute") }
  let(:seat) { create(:product, :fixed, organization: sandbox, product_category: category, code: "seat") }
  let(:seat_card) { create(:rate_card, organization: sandbox, product: seat, code: "seat_eur") }
  let(:support) { create(:product, :fixed, :standalone, organization: sandbox, code: "support") }
  let(:support_card) { create(:rate_card, organization: sandbox, product: support, code: "support_eur") }
  let(:vat) { create(:tax, organization: sandbox, code: "vat", rate: 20) }
  let(:live_vat) { create(:tax, organization: production, code: "vat", rate: 20) }
  let(:gst) { create(:tax, organization: sandbox, code: "gst", rate: 10) }
  let(:feature) { create(:feature, organization: sandbox, code: "seats") }
  let(:privilege) { create(:privilege, organization: sandbox, feature:, code: "max", value_type: "integer") }
  let(:wallet) do
    create(:plan_wallet, organization: sandbox, catalog_plan: plan, code: "credits", name: "Credits", priority: 10,
      tax_application: "tax_on_purchase")
  end
  let(:plan_seat) { create(:plan_rate_card, organization: sandbox, catalog_plan: plan, rate_card: seat_card, units: 2) }

  before do
    live_vat
    create(:rate_card_rate, organization: sandbox, rate_card: seat_card, code: "seat_rate")
    create(:rate_card_rate, organization: sandbox, rate_card: support_card, code: "support_rate")
    create(:plan_applied_tax, :catalog_plan, organization: sandbox, catalog_plan: plan, tax: vat)
    entitlement = create(:entitlement, :catalog_plan, organization: sandbox, catalog_plan: plan, feature:)
    create(:entitlement_value, organization: sandbox, entitlement:, privilege:, value: "10")

    override = create(:rate_override, organization: sandbox, rate_properties: {"amount" => "5"})
    create(:rate_phase, organization: sandbox, plan_rate_card: plan_seat, code: "trial", position: 1,
      billing_interval_cycle_count: 1, rate_override: override)
    create(:rate_phase, organization: sandbox, plan_rate_card: plan_seat, code: "default", position: 2)
    create(:rate_phase, organization: sandbox,
      plan_rate_card: create(:plan_rate_card, organization: sandbox, catalog_plan: plan, rate_card: support_card),
      code: "default", position: 1)

    create(:catalog_wallet_applied_tax, :plan_level, organization: sandbox, plan_wallet: wallet, tax: gst)
    create(:catalog_wallet_selector, :plan_level, organization: sandbox, plan_wallet: wallet, selector_type: "fee_type",
      fee_type: "fixed")
    create(:catalog_wallet_selector, :plan_level, organization: sandbox, plan_wallet: wallet,
      selector_type: "product_category", fee_type: nil, product_category: category)
    create(:plan_wallet_credit_allocation, organization: sandbox, plan_wallet: wallet, product: support, code: "monthly",
      billing_cycles: 3, credit_amount_cents: 5_000, priority: 5)
    create(:item_metadata, organization: sandbox, owner: wallet, value: {"tier" => "gold"})
    alert = create(:plan_wallet_alert, organization: sandbox, plan_wallet: wallet, code: "low", name: "Low")
    create(:catalog_wallet_alert_threshold, :template, organization: sandbox, plan_wallet_alert: alert, code: "warn",
      value: 1_000, notify_on: %w[triggered resolved])
  end
end
