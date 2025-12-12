# frozen_string_literal: true

subscription = Subscription.find_by!(external_id: "sub_john-doe-main")
subscription.plan.usage_thresholds.update_all(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
Plans::UpdateService.call!(
  plan: subscription.plan,
  params: {
    usage_thresholds: [{
      amount_cents: 120_00,
      threshold_display_name: "Initial Threshold"
    }, {
      amount_cents: 1_000_00,
      threshold_display_name: "Initial Threshold",
      recurring: true
    }]
  }
)

Subscriptions::UpdateUsageThresholdsService.call!(
  subscription:,
  usage_thresholds_params: [{
    amount_cents: 400_00,
    threshold_display_name: "Initial Threshold"
  }, {
    amount_cents: 800_00
  }, {
    amount_cents: 2000_00,
    recurring: true
  }],
  partial: false
)
