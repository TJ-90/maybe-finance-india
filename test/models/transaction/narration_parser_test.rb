require "test_helper"

class Transaction::NarrationParserTest < ActiveSupport::TestCase
  # All narrations are synthetic. Expected values are
  # [payment_mode, counterparty, vpa, reference_number, clean_name].
  SAMPLES = {
    "UPI hyphen format (HDFC style)" => [
      "UPI-SWIGGY-swiggy@icici-ICIC0000001-412345678901-UPI",
      [ "upi", "Swiggy", "swiggy@icici", "412345678901", "Swiggy" ]
    ],
    "UPI hyphen format with a person and a note" => [
      "UPI-RAHUL SHARMA-rahul.s@okhdfcbank-HDFC0001234-412345678902-Payment for dinner",
      [ "upi", "Rahul Sharma", "rahul.s@okhdfcbank", "412345678902", "Rahul Sharma" ]
    ],
    "UPI slash format with DR marker" => [
      "UPI/412345678901/DR/Swiggy/YESB/swiggy@yesbank/Order",
      [ "upi", "Swiggy", "swiggy@yesbank", "412345678901", "Swiggy" ]
    ],
    "UPI slash format with CR marker first" => [
      "UPI/CR/412345678903/PRIYA NAIR/HDFC/priya@okaxis/Refund",
      [ "upi", "Priya Nair", "priya@okaxis", "412345678903", "Priya Nair" ]
    ],
    "UPI slash format with P2M marker" => [
      "UPI/P2M/412345678904/BigBasket/UTIB/bigbasket@axisbank",
      [ "upi", "Bigbasket", "bigbasket@axisbank", "412345678904", "Bigbasket" ]
    ],
    "UPI with SBI transfer prefix" => [
      "TO TRANSFER-UPI/DR/412345678905/ZOMATO/HDFC/zomato@hdfcbank/Food",
      [ "upi", "Zomato", "zomato@hdfcbank", "412345678905", "Zomato" ]
    ],
    "NEFT credit with IFSC" => [
      "NEFT CR-HDFC0001234-ACME PVT LTD-RAHUL SHARMA-HDFCN52024010112345",
      [ "neft", "Acme Pvt Ltd", nil, "HDFCN52024010112345", "Acme Pvt Ltd" ]
    ],
    "NEFT debit (ICICI style)" => [
      "NEFT-ICIC0000001-LANDLORD NAME-N123456789012-RENT",
      [ "neft", "Landlord Name", nil, "N123456789012", "Landlord Name" ]
    ],
    "IMPS" => [
      "IMPS-412345678906-RAHUL SHARMA-HDFC-XXXXXXXX1234-Rent",
      [ "imps", "Rahul Sharma", nil, "412345678906", "Rahul Sharma" ]
    ],
    "IMPS with MMT prefix" => [
      "MMT/IMPS/412345678907/Rent/SURESH KUMAR",
      [ "imps", "Rent", nil, "412345678907", "Rent" ]
    ],
    "RTGS" => [
      "RTGS CR-SBIN0001234-GLOBAL TRADERS LLP-SBINR52024010100012",
      [ "rtgs", "Global Traders LLP", nil, "SBINR52024010100012", "Global Traders LLP" ]
    ],
    "ACH debit for BSE (SIP mandate)" => [
      "ACH D- BSE LIMITED-ICCL1234567890",
      [ "nach", "BSE Limited", nil, "ICCL1234567890", "BSE Limited" ]
    ],
    "NACH mutual fund SIP" => [
      "NACH-MF-HDFC AMC SIP-123456789012",
      [ "nach", "HDFC AMC SIP", nil, "123456789012", "HDFC AMC SIP" ]
    ],
    "ACH third-party EMI debit" => [
      "ACH D- TP ACH BAJAJ FINANCE EMI-LN12345678",
      [ "nach", "Bajaj Finance EMI", nil, "LN12345678", "Bajaj Finance EMI" ]
    ],
    "ACH credit" => [
      "ACH C- INFOSYS LTD-SAL JAN",
      [ "nach", "Infosys Ltd", nil, nil, "Infosys Ltd" ]
    ],
    "POS card purchase" => [
      "POS 416021XXXXXX1234 SWIGGY BANGALORE",
      [ "card", "Swiggy Bangalore", nil, nil, "Swiggy Bangalore" ]
    ],
    "ECOM card purchase" => [
      "ECOM PUR/AMAZON PAY INDIA/MUMBAI",
      [ "card", "Amazon Pay India", nil, nil, "Amazon Pay India" ]
    ],
    "ATM withdrawal (own bank)" => [
      "ATW-416021XXXXXX1234-S1ANBG12-BANGALORE",
      [ "atm", nil, nil, nil, "ATM withdrawal" ]
    ],
    "ATM withdrawal (other bank)" => [
      "NWD-512345XXXXXX9876-ABCD1234-MUMBAI",
      [ "atm", nil, nil, nil, "ATM withdrawal" ]
    ],
    "Cheque payment" => [
      "CHQ PAID-MICR CTS-123456-RAHUL SHARMA",
      [ "cheque", nil, nil, "123456", "Cheque payment 123456" ]
    ],
    "Cheque deposit" => [
      "CHQ DEP 654321 - LOCAL CLEARING",
      [ "cheque", nil, nil, "654321", "Cheque deposit 654321" ]
    ],
    "Cash deposit" => [
      "CASH DEP-BRANCH-MG ROAD",
      [ "cash", nil, nil, nil, "Cash deposit" ]
    ],
    "Interest credit (INT.PD)" => [
      "INT.PD:01-01-2024 TO 31-03-2024",
      [ "other", nil, nil, nil, "Interest credit" ]
    ],
    "Interest credit (Int.Pd mixed case)" => [
      "Int.Pd:01-04-2024 to 30-06-2024",
      [ "other", nil, nil, nil, "Interest credit" ]
    ],
    "Bank charges" => [
      "SMS ALERT CHARGES 01-24",
      [ "other", nil, nil, nil, "Bank charges" ]
    ],
    "GST on charges" => [
      "GST @ 18% ON CHARGES",
      [ "other", nil, nil, nil, "Bank charges" ]
    ],
    "Fee text inside a NEFT narration is not treated as a bank charge" => [
      "NEFT DR-HDFC0001234-DPS SCHOOL-NETBANK, MUM-N123456789012-SCHOOL FEE",
      [ "neft", "Dps School", nil, "N123456789012", "Dps School" ]
    ]
  }.freeze

  SAMPLES.each do |description, (narration, expected)|
    test "parses: #{description}" do
      parsed = Transaction::NarrationParser.parse(narration)

      assert_equal(
        {
          payment_mode: expected[0],
          counterparty: expected[1],
          vpa: expected[2],
          reference_number: expected[3],
          clean_name: expected[4]
        },
        parsed,
        "unexpected parse for #{narration.inspect}"
      )
    end
  end

  test "has at least 15 samples" do
    assert_operator SAMPLES.size, :>=, 15
  end

  test "unrecognised narration returns nil fields" do
    parsed = Transaction::NarrationParser.parse("Grocery Store")

    assert_nil parsed[:payment_mode]
    assert_nil parsed[:clean_name]
    assert_nil parsed[:counterparty]
  end

  test "blank narration returns nil fields" do
    assert_equal Transaction::NarrationParser::EMPTY, Transaction::NarrationParser.parse(nil)
    assert_equal Transaction::NarrationParser::EMPTY, Transaction::NarrationParser.parse("   ")
  end

  test "payment modes are all part of the allowed list" do
    SAMPLES.each_value do |(narration, _)|
      mode = Transaction::NarrationParser.parse(narration)[:payment_mode]
      assert_includes Transaction::PAYMENT_MODES, mode
    end
  end
end
