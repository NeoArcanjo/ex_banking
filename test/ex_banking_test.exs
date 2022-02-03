defmodule ExBankingTest do
  @moduledoc """
  This module is used to test the ExBanking module.
  """

  use ExUnit.Case, async: true
  alias ExBanking.Client

  # doctest ExBanking

  describe "Testing 'create_user/1'" do
    test "Creating a new user" do
      ExBanking.create_user("test")
      assert Client.exists?("test")
    end

    test "Recusing duplicate user" do
      ExBanking.create_user("test")
      assert {:error, :user_already_exists} = ExBanking.create_user("test")
    end

    test "User name is case sensitive" do
      ExBanking.create_user("test")
      assert Client.exists?("test")
      refute Client.exists?("Test")
      ExBanking.create_user("Test")
      assert Client.exists?("Test")
    end

    test "Recusing a not string user name" do
      assert {:error, :wrong_arguments} = ExBanking.create_user(1)
    end
  end

  describe "Testing 'get_balance" do
    setup do
      ExBanking.create_user("test balance")
      :ok
    end

    test "Getting the balance of a existing user" do
      ExBanking.deposit("test balance", 100.00, "EUR")
      assert is_number(ExBanking.get_balance("test balance", "EUR"))
      assert is_number(ExBanking.get_balance("test balance", "USD"))
    end

    test "Error when getting the balance of a not existing user" do
      assert {:error, :user_does_not_exist} = ExBanking.get_balance("test2", "EUR")
    end
  end

  describe "Testing deposit/3" do
    setup do
      ExBanking.create_user("trader")
      :ok
    end

    test "Depositing money to an existing user" do
      current_balance = ExBanking.get_balance("trader", "EUR")
      euros = ExBanking.deposit("trader", 100.00, "EUR")
      assert current_balance + 100.00 == euros
      assert current_balance + 100.00 == ExBanking.get_balance("trader", "EUR")
    end

    test "Multiple currencies" do
      euro_balance = ExBanking.get_balance("trader", "EUR")
      dolar_balance = ExBanking.get_balance("trader", "USD")
      real_balance = ExBanking.get_balance("trader", "BRL")

      euros = ExBanking.deposit("trader", 100.00, "EUR")
      dolars = ExBanking.deposit("trader", 200.00, "USD")
      real = ExBanking.deposit("trader", 500.00, "BRL")

      assert real_balance + 500.00 == ExBanking.get_balance("trader", "BRL")
      assert real_balance + 500.00 == real
      assert euro_balance + 100.00 == euros
      assert euro_balance + 100.00 == ExBanking.get_balance("trader", "EUR")
      assert dolar_balance + 200.00 == dolars
      assert dolar_balance + 200.00 == ExBanking.get_balance("trader", "USD")
    end

    test "Error when depositing money to a not existing user" do
      assert {:error, :user_does_not_exist} = ExBanking.deposit("test2", 100.00, "EUR")
    end

    test "Error when depositing money with a not string currency" do
      assert {:error, :wrong_arguments} = ExBanking.deposit("test", 100.00, 1)
    end
  end

  describe "Testing withdraw/3" do
    setup do
      ExBanking.create_user("test")
      ExBanking.deposit("test", 100.00, "EUR")
      :ok
    end

    test "Withdrawing money from an existing user" do
      currency = "EUR"
      current_balance = ExBanking.get_balance("test", currency)
      ExBanking.withdraw("test", 100.00, currency)
      assert current_balance - 100.00 == ExBanking.get_balance("test", currency)
    end

    test "Error when withdrawing money from a not existing user" do
      assert {:error, :user_does_not_exist} = ExBanking.withdraw("test2", 100.00, "EUR")
    end

    test "Error when withdrawing money with a not string currency" do
      assert {:error, :wrong_arguments} = ExBanking.withdraw("test", 100.00, 1)
    end
  end

  describe "Sending money between users" do
    setup do
      ExBanking.create_user("sender")
      ExBanking.create_user("poor boy")
      ExBanking.create_user("receiver")
      ExBanking.deposit("sender", 100.00, "EUR")
      ExBanking.deposit("receiver", 100.00, "EUR")
      :ok
    end

    test "Sending money between existing users and positive balance in origin" do
      current_balance_from = ExBanking.get_balance("sender", "EUR")
      current_balance_to = ExBanking.get_balance("receiver", "EUR")

      assert {:ok, new_from, new_to} = ExBanking.send("sender", "receiver", 50.00, "EUR")

      assert current_balance_from - 50.00 == ExBanking.get_balance("sender", "EUR")
      assert current_balance_from - 50.00 == new_from
      assert current_balance_to + 50.00 == ExBanking.get_balance("receiver", "EUR")
      assert current_balance_to + 50.00 == new_to
    end

    test "Error when sending more money that in wallet" do
      current_balance_from = ExBanking.get_balance("poor boy", "EUR")
      current_balance_to = ExBanking.get_balance("receiver", "EUR")

      assert :not_enough_money = ExBanking.send("poor boy", "receiver", 5_000_000.00, "EUR")

      assert current_balance_from == ExBanking.get_balance("poor boy", "EUR")
      assert current_balance_to == ExBanking.get_balance("receiver", "EUR")
    end

    test "Error when not exists sender" do
      current_balance_to = ExBanking.get_balance("receiver", "EUR")
      assert {:error, :sender_does_not_exist} = ExBanking.send("from2", "receiver", 100.00, "EUR")
      assert current_balance_to == ExBanking.get_balance("receiver", "EUR")
    end

    test "Error when not exists receiver" do
      current_balance_from = ExBanking.get_balance("sender", "EUR")
      assert {:error, :receiver_does_not_exist} = ExBanking.send("sender", "to2", 100.00, "EUR")
      assert current_balance_from == ExBanking.get_balance("sender", "EUR")
    end
  end

  describe "Testing max rating" do
    setup do
      ExBanking.create_user("Scrooge McDuck")
      ExBanking.create_user("Richie Rich")
      :ok
    end

    @tag timeout: :infinity
    test "Money's rain" do
      value = 1.00
      deposits = 300

      total_amount =
        ExBanking.get_balance("Scrooge McDuck", "USD") +
          ExBanking.get_balance("Richie Rich", "USD")

      1..deposits
      |> Task.async_stream(fn num ->
        ExBanking.deposit("Scrooge McDuck", value, "USD")
        ExBanking.deposit("Scrooge McDuck", value, "USD")
        ExBanking.deposit("Scrooge McDuck", value, "USD")
        ExBanking.deposit("Richie Rich", value * 2, "USD")
      end)
      |> Enum.to_list()

      assert deposits * value * 3 == ExBanking.get_balance("Scrooge McDuck", "USD")
      assert deposits * value * 2 == ExBanking.get_balance("Richie Rich", "USD")

      total_amount = deposits * value * 5
    end

    @tag timeout: :infinity
    test "Money's rain with transfer" do
      value = 6.00
      deposits = 3_000

      ExBanking.deposit("Richie Rich", value * 10_000, "BRL")

      total_amount =
        ExBanking.get_balance("Scrooge McDuck", "BRL") +
          ExBanking.get_balance("Richie Rich", "BRL")

      1..deposits
      |> Stream.map(fn num ->
        ExBanking.send("Richie Rich", "Scrooge McDuck", value / Enum.random(1..5), "BRL")
      end)
      |> Stream.run()

      assert Money.parse!(ExBanking.get_balance("Scrooge McDuck", "BRL"), "BRL") ==
               Money.parse!(total_amount - ExBanking.get_balance("Richie Rich", "BRL"), "BRL")

      assert total_amount ==
               ExBanking.get_balance("Richie Rich", "BRL") +
                 ExBanking.get_balance("Scrooge McDuck", "BRL")

      assert total_amount == value * 10_000
    end
  end
end
