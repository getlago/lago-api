# frozen_string_literal: true

class CreditNotesQuery < BaseQuery
  def call
    credit_notes = base_scope.result
    credit_notes = paginate(credit_notes)
    credit_notes = credit_notes.order(created_at: :desc)

    # ensure consistent order on credit_notes with the same created_at
    credit_notes = credit_notes.order(id: :asc)

    credit_notes = with_customer_id(credit_notes) if filters.customer_id.present?
    credit_notes = with_external_customer_id(credit_notes) if filters.external_customer_id.present?

    result.credit_notes = credit_notes
    result
  end

  private

  def base_scope
    CreditNote
      .joins(:customer)
      .where('customers.organization_id = ?', organization.id)
      .finalized
      .ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    {
      m: 'or',
      number_cont: search_term,
      id_cont: search_term
    }
  end

  def with_customer_id(scope)
    scope.where(customer_id: filters.customer_id)
  end

  def with_external_customer_id(scope)
    scope.joins(:customer).where(customers: {external_id: filters.external_customer_id})
  end
end
