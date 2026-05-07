# frozen_string_literal: true

RSpec.shared_examples "applies invoice_custom_sections" do
  let(:invoice_custom_sections) { create_list(:invoice_custom_section, 4, organization:) }

  before do
    invoice_custom_sections[2..3].each do |section|
      create(:billing_entity_applied_invoice_custom_section, organization:, billing_entity:, invoice_custom_section: section)
    end
  end

  context "when the customer has :skip_invoice_custom_sections flag" do
    before { customer.update!(skip_invoice_custom_sections: true) }

    it "doesn't create applied_invoice_custom_section" do
      expect { service_call }.not_to change(AppliedInvoiceCustomSection, :count)
    end
  end

  context "when customer follows billing_entity invoice_custom_sections" do
    it "creates applied_invoice_custom_sections" do
      result = service_call
      invoice = result.invoice
      expect(invoice.applied_invoice_custom_sections.pluck(:code)).to match_array(billing_entity.selected_invoice_custom_sections.pluck(:code))
    end
  end
end

# Shared example to assert that the resource (subscription, wallet, wallet_transaction,
# or recurring_transaction_rule) has its custom sections applied to the generated invoice
# instead of falling back to the customer's or billing entity's sections.
#
# The spec must define:
# - `service_call`: invokes the service under test and returns its result
# - `resource_with_custom_section`: the resource (subscription, wallet, etc) attached to the invoice
# - `applied_section_factory`: factory name (Symbol) for the join model linking the resource to the section
# - `resource_association_key`: keyword used by that factory to attach the resource (e.g. :subscription)
RSpec.shared_examples "applies invoice_custom_sections from resource" do
  let(:resource_invoice_custom_section) { create(:invoice_custom_section, organization:) }

  before do
    other_section = create(:invoice_custom_section, organization:)
    create(:billing_entity_applied_invoice_custom_section, organization:, billing_entity:, invoice_custom_section: other_section)
    create(
      applied_section_factory,
      organization:,
      resource_association_key => resource_with_custom_section,
      invoice_custom_section: resource_invoice_custom_section
    )
  end

  it "applies the resource's invoice_custom_sections to the invoice" do
    result = service_call
    invoice = result.invoice
    expect(invoice.applied_invoice_custom_sections.pluck(:code)).to eq([resource_invoice_custom_section.code])
  end
end
