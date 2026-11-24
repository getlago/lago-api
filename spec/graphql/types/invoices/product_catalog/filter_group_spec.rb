# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Invoices::ProductCatalog::FilterGroup do
  subject { described_class }

  it do
    expect(subject).to have_field(:product_filter).of_type("ProductFilter!")
    expect(subject).to have_field(:amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:fees_count).of_type("Int!")
  end
end
