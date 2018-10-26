class AddPaymentDetailsToSource < SolidusSupport::Migration[4.2]
  def up
    change_table :solidus_paypal_braintree_sources do |t|
      t.references :payment_details, polymorphic: true
    end
  end

  def down
    change_table :solidus_paypal_braintree_sources do |t|
      t.remove_references :payment_details, polymorphic: true
    end
  end
end
