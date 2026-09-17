# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::PaymentProviderCustomers::ConnectionStatusEnum do
  it "enumerates the correct values" do
    expect(described_class.values.keys).to match_array(%w[not_connected manual connected])
  end
end
