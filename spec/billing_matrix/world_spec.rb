# frozen_string_literal: true

require "rails_helper"
require_relative "../../billing_matrix/runner/world"

RSpec.describe BillingMatrix::World, type: :request do
  # Reuse the request helpers without importing Context, whose boot clears the database.
  attr_accessor :organization, :billing_entity, :tax, :billable_metric, :customer, :coupon, :wallet

  def premium?
    false
  end

  it "applies a tax declared in the same setup to the billing entity" do
    setup = {
      "taxes" => [{"code" => "vat", "rate" => 20, "applied_to_organization" => false}],
      "billing_entity" => {"tax_codes" => ["vat"]}
    }

    described_class.build!(self, setup)

    expect(billing_entity.reload.taxes.pluck(:code)).to eq(["vat"])
  end
end
