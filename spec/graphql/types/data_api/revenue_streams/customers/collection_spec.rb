# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::DataApi::RevenueStreams::Customers::Collection do
  subject { described_class }

  it do
    expect(subject.graphql_name).to eq("DataApiRevenueStreamsCustomers")
    expect(subject).to have_field(:revenue_streams_customers).of_type("DataApiRevenueStreamCustomerCollection!")
    expect(subject).to have_field(:meta).of_type("DataApiMetadata!")
  end
end
