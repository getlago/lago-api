# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscription::UsageActivity, type: :model do
  subject { create(:subscription_usage_activity) }

  it do
    expect(subject).to belong_to(:subscription)
    expect(subject).to belong_to(:organization)
  end
end
