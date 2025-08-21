# frozen_string_literal: true

module XMLHelper
  NAMESPACES = {
    factur_x: EInvoices::FacturX::Create::Builder::ROOT_NAMESPACES,
    ubl: EInvoices::Ubl::Create::Builder::ROOT_NAMESPACES
  }

  def xml_document(ns)
    Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
      xml.TestRoot(NAMESPACES[ns]) do
        yield xml
      end
    end.doc
  end

  def xml_fragment(ns, &block)
    xml_document(ns, &block).root.children.to_xml(
      save_with: Nokogiri::XML::Node::SaveOptions::NO_DECLARATION
    )
  end
end
