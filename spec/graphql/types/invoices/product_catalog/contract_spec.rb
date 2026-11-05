# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Invoices::ProductCatalog::Contract do
  subject { described_class }

  it do
    expect(subject).to have_field(:contract).of_type("Contract!")
    expect(subject).to have_field(:product_catalog_sections).of_type("[InvoiceProductCatalogSection!]!")
  end
end
