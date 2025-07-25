# frozen_string_literal: true

RSpec::Matchers.define :xml_document_have_node do |xpath, value|
  match do |document|
    @xpath = xpath
    @value = value
    @node = document.at_xpath(xpath)
    @node && (@value.nil? || @node.text == @value.to_s)
  end

  failure_message do |document|
    if @node.nil?
      "expected XPath #{@xpath} to be present, but it was not found in the XML"
    else
      "expected XPath #{@xpath} to have value #{@value}, but was #{@node.text}"
    end
  end
end

RSpec::Matchers.define :xml_document_have_comment do |comment|
  match do |document|
    document.xpath("//comment()").map(&:text).include?(comment)
  end
end

RSpec::Matchers.define :xml_node_have_attribute do |xpath, name, value|
  match do |document|
    node = document.at_xpath(xpath)
    attribute = node.attributes[name]
    attribute && (value.nil? || attribute.value == value.to_s)
  end
end
