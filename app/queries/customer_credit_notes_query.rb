# frozen_string_literal: true

class CustomerCreditNotesQuery < BaseQuery
  def call(customer_id:, search_term:, page:, limit:, filters: {})
    @search_term = search_term

    credit_notes = base_scope(customer_id:).result
    credit_notes = credit_notes.where(id: filters[:ids]) if filters[:ids].present?
    credit_notes = credit_notes.order(issuing_date: :desc).page(page).per(limit)

    result.credit_notes = credit_notes
    result
  end

  private

  attr_reader :search_term

  def base_scope(customer_id:)
    Customer.find(customer_id).credit_notes.finalized.ransack(search_params)
  end

  def search_params
    return nil if search_term.blank?

    {
      m: 'or',
      number_cont: search_term,
      id_cont: search_term
    }
  end
end
