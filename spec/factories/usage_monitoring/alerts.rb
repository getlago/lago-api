FactoryBot.define do
  factory :usage_monitoring_alert, class: 'UsageMonitoring::Alert' do
    subscription_external_id { "MyString" }
  end
end
