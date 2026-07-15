# frozen_string_literal: true

require "rails_helper"

RSpec.describe "templates/invoices/v4/_graduated_percentage.slim", :premium do
  subject(:rendered_template) do
    Slim::Template.new(template, 1, pretty: true).render(fee)
  end

  let(:template) { Rails.root.join("app/views/templates/invoices/v4/_graduated_percentage.slim") }

  let(:organization) { create(:organization, :with_static_values) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, plan:) }
  let(:charge) { create(:graduated_percentage_charge, plan:, billable_metric:) }

  let(:fee) do
    create(
      :charge_fee,
      charge:,
      subscription:,
      amount_cents: 1174,
      amount_currency: "USD",
      units: 11.77001111111111111111107306,
      invoice_display_name: "Query (hours)",
      amount_details: {
        "graduated_percentage_ranges" => [
          {
            "from_value" => 0,
            "to_value" => 2,
            "units" => "2.0",
            "rate" => "1.0",
            "per_unit_total_amount" => "0.02",
            "flat_unit_amount" => "0.0"
          },
          {
            "from_value" => 2,
            "to_value" => 10,
            "units" => "4.77001111111111111111107306",
            "rate" => "1.0",
            "per_unit_total_amount" => "0.05",
            "flat_unit_amount" => "0.0"
          },
          {
            "from_value" => 10,
            "to_value" => nil,
            "units" => "5.123456789123",
            "rate" => "1.0",
            "per_unit_total_amount" => "0.05",
            "flat_unit_amount" => "0.0"
          }
        ]
      }
    )
  end

  it "rounds the units column to six decimals for display" do
    expect(rendered_template).to include("4.770011")
    expect(rendered_template).to include("5.123457")
    expect(rendered_template).not_to include("4.77001111111111111111107306")
    expect(rendered_template).not_to include("5.123456789123")
  end
end
