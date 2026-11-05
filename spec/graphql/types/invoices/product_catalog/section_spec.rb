# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Invoices::ProductCatalog::Section do
  subject { described_class }

  it do
    expect(subject).to have_field(:product_category).of_type("ProductCategory")
    expect(subject).to have_field(:products).of_type("[InvoiceProductCatalogProductGroup!]!")
  end
end
