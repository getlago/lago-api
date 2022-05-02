# frozen_string_literal: true

require 'factory_bot_rails'

return if User.find_by(email: 'gavin@hooli.com').present?

user = User.create!(email: 'gavin@hooli.com', password: 'ILoveLago')
organization = Organization.find_or_create_by(name: 'Hooli')
Membership.find_or_create_by(user: user, organization: organization, role: :admin)

customers = FactoryBot.create_list(:customer, 5, organization: organization)
subscriptions = []
customers.each do |customer|
  subscriptions << FactoryBot.create(:subscription, customer: customer, started_at: Time.zone.now - 3.months, status: :active)
end

Subscription.all.find_each do |subscription|
  Invoices::CreateService.new(
    subscription: subscription,
    timestamp: Time.zone.now - 2.months,
  ).create
end
