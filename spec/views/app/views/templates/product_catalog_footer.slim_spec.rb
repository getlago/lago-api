# frozen_string_literal: true

require "rails_helper"

RSpec.describe "templates/_product_catalog_footer.slim" do
  subject(:rendered_footers) do
    [
      render_footer("invoices/product_catalog/footer", invoice),
      render_footer("credit_notes/product_catalog/footer", credit_note)
    ].map { |html| Nokogiri::HTML(html) }
  end

  let(:invoice) { Struct.new(:number).new("INV-123 <&>") }
  let(:credit_note) { Struct.new(:number).new("CN-123") }

  it "shares the footer style and page numbering while preserving each document reference" do
    invoice_footer, credit_note_footer = rendered_footers
    page_numbering = I18n.t("document.page_numbering", current: '<span class="pageNumber"></span>', total: '<span class="totalPages"></span>')

    expect(invoice_footer.at_css(".footer span").text).to eq("INV-123 <&>")
    expect(credit_note_footer.at_css(".footer span").text).to eq("#{I18n.t("credit_note.document_name")} CN-123")
    expect(invoice_footer.at_css("style").text).to eq(credit_note_footer.at_css("style").text)
    expect(invoice_footer.at_css(".footer span:nth-child(2)").inner_html).to eq(page_numbering)
    expect(credit_note_footer.at_css(".footer span:nth-child(2)").inner_html).to eq(page_numbering)
  end

  def render_footer(path, context)
    Slim::Template.new(Rails.root.join("app/views/templates/#{path}.slim").to_s).render(context)
  end
end
