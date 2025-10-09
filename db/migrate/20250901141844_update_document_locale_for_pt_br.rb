# frozen_string_literal: true

class UpdateDocumentLocaleForPtBr < ActiveRecord::Migration[8.0]
  def up
    Organization.where(document_locale: "pt_BR").update(document_locale: "pt-BR")
    BillingEntity.where(document_locale: "pt_BR").update(document_locale: "pt-BR")
    Customer.where(document_locale: "pt_BR").update(document_locale: "pt-BR")
  end

  def down
    Organization.where(document_locale: "pt-BR").update(document_locale: "pt_BR")
    BillingEntity.where(document_locale: "pt-BR").update(document_locale: "pt_BR")
    Customer.where(document_locale: "pt-BR").update(document_locale: "pt_BR")
  end
end
