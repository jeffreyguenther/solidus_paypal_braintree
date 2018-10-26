require 'spec_helper'

RSpec.describe SolidusPaypalBraintree::Source, type: :model do
  it 'is invalid without a payment_type set' do
    expect(described_class.new).to be_invalid
  end

  it 'is invalid with payment_type set to unknown type' do
    expect(described_class.new(payment_type: 'AndroidPay')).to be_invalid
  end

  describe '#payment_method' do
    it 'uses spree_payment_method' do
      expect(described_class.new.build_payment_method).to be_a Spree::PaymentMethod
    end
  end

  describe '#imported' do
    it 'is always false' do
      expect(described_class.new.imported).to_not be
    end
  end

  describe "#actions" do
    it "supports capture, void, and credit" do
      expect(described_class.new.actions).to eq %w[capture void credit]
    end
  end

  describe "#can_capture?" do
    subject { described_class.new.can_capture?(payment) }

    context "when the payment state is pending" do
      let(:payment) { build(:payment, state: "pending") }

      it { is_expected.to be }
    end

    context "when the payment state is checkout" do
      let(:payment) { build(:payment, state: "checkout") }

      it { is_expected.to be }
    end

    context "when the payment is completed" do
      let(:payment) { build(:payment, state: "completed") }

      it { is_expected.to_not be }
    end
  end

  describe '#can_void?' do
    let(:payment_source) { described_class.new }
    let(:payment) { build(:payment) }

    let(:transaction_response) do
      double(status: Braintree::Transaction::Status::SubmittedForSettlement)
    end

    let(:transaction_request) do
      double(find: transaction_response)
    end

    subject { payment_source.can_void?(payment) }

    before do
      allow(payment_source).to receive(:braintree_client) do
        double(transaction: transaction_request)
      end
    end

    context 'when transaction id is not present' do
      let(:payment) { build(:payment, response_code: nil) }

      it { is_expected.to be(false) }
    end

    context 'when transaction has voidable status' do
      it { is_expected.to be(true) }
    end

    context 'when transaction has non voidable status' do
      let(:transaction_response) do
        double(status: Braintree::Transaction::Status::Settled)
      end

      it { is_expected.to be(false) }
    end

    context 'when transaction is not found at Braintreee' do
      before do
        allow(transaction_request).to \
          receive(:find).and_raise(Braintree::NotFoundError)
      end

      it { is_expected.to be(false) }
    end
  end

  describe "#can_credit?" do
    subject { described_class.new.can_credit?(payment) }

    context "when the payment is completed" do
      context "and the credit allowed is 100" do
        let(:payment) { build(:payment, state: "completed", amount: 100) }

        it { is_expected.to be }
      end

      context "and the credit allowed is 0" do
        let(:payment) { build(:payment, state: "completed", amount: 0) }

        it { is_expected.not_to be }
      end
    end

    context "when the payment has not been completed" do
      let(:payment) { build(:payment, state: "checkout") }

      it { is_expected.not_to be }
    end
  end

  describe "#friendly_payment_type" do
    subject { described_class.new(payment_type: type).friendly_payment_type }

    context "when then payment type is PayPal" do
      let(:type) { "PayPalAccount" }

      it "returns the translated payment type" do
        expect(subject).to eq "PayPal"
      end
    end

    context "when the payment type is Apple Pay" do
      let(:type) { "ApplePayCard" }

      it "returns the translated payment type" do
        expect(subject).to eq "Apple Pay"
      end
    end

    context "when the payment type is Credit Card" do
      let(:type) { "CreditCard" }

      it "returns the translated payment type" do
        expect(subject).to eq "Credit Card"
      end
    end
  end

  describe "#apple_pay?" do
    subject { described_class.new(payment_type: type).apple_pay? }

    context "when the payment type is Apple Pay" do
      let(:type) { "ApplePayCard" }

      it { is_expected.to be true }
    end

    context "when the payment type is not Apple Pay" do
      let(:type) { "DogeCoin" }

      it { is_expected.to be false }
    end
  end

  describe "#paypal?" do
    subject { described_class.new(payment_type: type).paypal? }

    context "when the payment type is PayPal" do
      let(:type) { "PayPalAccount" }

      it { is_expected.to be true }
    end

    context "when the payment type is not PayPal" do
      let(:type) { "MonopolyMoney" }

      it { is_expected.to be false }
    end
  end

  describe "#credit_card?" do
    subject { described_class.new(payment_type: type).credit_card? }

    context "when the payment type is CreditCard" do
      let(:type) { "CreditCard" }

      it { is_expected.to be true }
    end

    context "when the payment type is not CreditCard" do
      let(:type) { "MonopolyMoney" }

      it { is_expected.to be false }
    end
  end

  shared_context 'unknown source token' do
    let(:braintree_payment_method) { double }

    before do
      allow(braintree_payment_method).to receive(:find) do
        raise Braintree::NotFoundError
      end
      allow(payment_source).to receive(:braintree_client) do
        double(payment_method: braintree_payment_method)
      end
    end
  end

  shared_context 'nil source token' do
    let(:braintree_payment_method) { double }

    before do
      allow(braintree_payment_method).to receive(:find) do
        raise ArgumentError
      end
      allow(payment_source).to receive(:braintree_client) do
        double(payment_method: braintree_payment_method)
      end
    end
  end

  describe "#last_4" do
    let(:method) { new_gateway.tap(&:save!) }
    let(:payment_source) { described_class.create!(payment_type: "CreditCard", payment_method: method) }
    let(:braintree_client) { method.braintree }

    subject { payment_source.last_4 }

    context 'when token is known at braintree', vcr: { cassette_name: "source/last4" } do
      before do
        customer = braintree_client.customer.create
        expect(customer.customer.id).to be

        method = braintree_client.payment_method.create({
          payment_method_nonce: "fake-valid-country-of-issuance-usa-nonce", customer_id: customer.customer.id
        })
        expect(method.payment_method.token).to be

        payment_source.update_attributes!(token: method.payment_method.token)
      end

      it "delegates to the payment_details" do
        method = braintree_client.payment_method.find(payment_source.token)
        expect(subject).to eql(method.last_4)
      end
    end

    context 'when the source token is not known at Braintree' do
      include_context 'unknown source token'

      it { is_expected.to be(nil) }
    end

    context 'when the source token is nil' do
      include_context 'nil source token'

      it { is_expected.to be(nil) }
    end
  end

  describe "#display_number" do
    let(:payment_source) { described_class.new }
    subject { payment_source.display_number }

    context "when last_digits is a number" do
      before do
        allow(payment_source).to receive(:last_digits).and_return('1234')
      end

      it { is_expected.to eq 'XXXX-XXXX-XXXX-1234' }
    end

    context "when last_digits is nil" do
      before do
        allow(payment_source).to receive(:last_digits).and_return(nil)
      end

      it { is_expected.to eq 'XXXX-XXXX-XXXX-XXXX' }
    end
  end

  describe "#card_type" do
    let(:method) { new_gateway.tap(&:save!) }
    let(:payment_source) { described_class.create!(payment_type: "CreditCard", payment_method: method) }
    let(:braintree_client) { method.braintree }

    subject { payment_source.card_type }

    context "when the token is known at braintree", vcr: { cassette_name: "source/card_type" } do
      before do
        customer = braintree_client.customer.create
        expect(customer.customer.id).to be

        method = braintree_client.payment_method.create({
          payment_method_nonce: "fake-valid-country-of-issuance-usa-nonce", customer_id: customer.customer.id
        })
        expect(method.payment_method.token).to be

        payment_source.update_attributes!(token: method.payment_method.token)
      end

      it "delegates to the payment details computed" do
        method = braintree_client.payment_method.find(payment_source.token)
        expect(subject).to eql(method.card_type)
      end
    end

    context 'when the source token is not known at Braintree' do
      include_context 'unknown source token'

      it { is_expected.to be_nil }
    end

    context 'when the source token is nil' do
      include_context 'nil source token'

      it { is_expected.to be_nil }
    end
  end

  describe '#payment_details_computed' do
    let(:method) { new_gateway.tap(&:save!) }
    let(:payment_source) { described_class.create!(payment_type: 'CreditCard', payment_method: method) }
    let(:braintree_client) { method.braintree }
    let(:dummy_credit_card) do
      double(
          'credit_card',
          card_type: 'card_type',
          expiration_month: 'expiration_month',
          expiration_year: 'expiration_year',
          cardholder_name: 'cardholder_name',
          last_4: 'last_4'
      )
    end
    let(:payment_method_gateway) { double('payment_method_gateway', find: dummy_credit_card) }

    shared_context 'credit card created' do
      it 'ensure a credit card record is created' do
        expect(payment_source.payment_details).to be_nil
        subject
        expect(payment_source.payment_details).to be
      end
    end

    context 'when credit_card attributes are accessed multiple times' do
      before do
        allow(braintree_client).to receive(:payment_method).and_return(payment_method_gateway)
      end

      context 'when last_digits is accessed multiple times' do
        include_context 'credit card created'
        subject do
          payment_source.last_digits
          payment_source.reload
          payment_source.last_digits
        end

        it 'ensures that braintree gateway is called just once' do
          expect(payment_method_gateway).to receive(:find).once
          expect(subject).to eql('last_4')
        end
      end

      context 'when year is accessed multiple times' do
        include_context 'credit card created'
        subject { 2.times.collect { payment_source.year }.last }

        it 'ensures that braintree gateway is called just once' do
          expect(payment_method_gateway).to receive(:find).once
          expect(subject).to eql('expiration_year')
        end
      end

      context 'when month is accessed multiple times' do
        include_context 'credit card created'
        subject { 2.times.collect { payment_source.month }.last }

        it 'ensures that braintree gateway is called just once' do
          expect(payment_method_gateway).to receive(:find).once
          expect(subject).to eql('expiration_month')
        end
      end

      context 'when name is accessed multiple times' do
        include_context 'credit card created'
        subject { 2.times.collect { payment_source.name }.last }

        it 'ensures that braintree gateway is called just once' do
          expect(payment_method_gateway).to receive(:find).once
          expect(subject).to eql('cardholder_name')
        end
      end

      context 'when cc_type is accessed multiple times' do
        include_context 'credit card created'
        subject { 2.times.collect { payment_source.cc_type }.last }

        it 'ensures that braintree gateway is called just once' do
          expect(payment_method_gateway).to receive(:find).once
          expect(subject).to eql('card_type')
        end
      end
    end
  end
end
