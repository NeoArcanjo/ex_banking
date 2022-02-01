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
      ExBanking.create_user("test")
      :ok
    end

    test "Getting the balance of a existing user" do
      ExBanking.deposit("test", 100.00, "EUR")
      assert is_number(ExBanking.get_balance("test", "EUR"))
      assert is_number(ExBanking.get_balance("test", "USD"))
    end

    test "Error when getting the balance of a not existing user" do
      assert {:error, :user_does_not_exist} = ExBanking.get_balance("test2", "EUR")
    end
  end

  describe "Testing deposit/3" do
    setup do
      ExBanking.create_user("test")
      :ok
    end

    test "Depositing money to an existing user" do
      current_balance = ExBanking.get_balance("test", "EUR")
      euros = ExBanking.deposit("test", 100.00, "EUR")
      assert current_balance + 100.00 == euros
      assert current_balance + 100.00 == ExBanking.get_balance("test", "EUR")
    end

    test "Multiple currencies" do
      euro_balance = ExBanking.get_balance("test", "EUR")
      dolar_balance = ExBanking.get_balance("test", "USD")
      real_balance = ExBanking.get_balance("test", "BRL")

      euros = ExBanking.deposit("test", 100.00, "EUR")
      dolars = ExBanking.deposit("test", 200.00, "USD")
      real = ExBanking.deposit("test", 500.00, "BRL")

      assert real_balance + 500.00 == ExBanking.get_balance("test", "BRL")
      assert real_balance + 500.00 == real
      assert euro_balance + 100.00 == euros
      assert euro_balance + 100.00 == ExBanking.get_balance("test", "EUR")
      assert dolar_balance + 200.00 == dolars
      assert dolar_balance + 200.00 == ExBanking.get_balance("test", "USD")
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
      ExBanking.create_user("from")
      ExBanking.create_user("to")
      ExBanking.deposit("from", 100.00, "EUR")
      ExBanking.deposit("to", 100.00, "EUR")
      :ok
    end

    test "Sending money between existing users and positive balance in origin" do
      current_balance_from = ExBanking.get_balance("from", "EUR")
      current_balance_to = ExBanking.get_balance("to", "EUR")

      assert {:ok, new_from, new_to} = ExBanking.send("from", "to", 50.00, "EUR")

      assert current_balance_from - 50.00 == ExBanking.get_balance("from", "EUR")
      assert current_balance_from - 50.00 == new_from
      assert current_balance_to + 50.00 == ExBanking.get_balance("to", "EUR")
      assert current_balance_to + 50.00 == new_to
    end

    test "Error when sending more money that in wallet" do
      current_balance_from = ExBanking.get_balance("from", "EUR")
      current_balance_to = ExBanking.get_balance("to", "EUR")

      assert :not_enough_money = ExBanking.send("from", "to", 5_000_000.00, "EUR")

      assert current_balance_from == ExBanking.get_balance("from", "EUR")
      assert current_balance_to == ExBanking.get_balance("to", "EUR")
    end

    test "Error when not exists sender" do
      current_balance_to = ExBanking.get_balance("to", "EUR")
      assert {:error, :sender_does_not_exist} = ExBanking.send("from2", "to", 100.00, "EUR")
      assert current_balance_to == ExBanking.get_balance("to", "EUR")
    end

    test "Error when not exists receiver" do
      current_balance_from = ExBanking.get_balance("from", "EUR")
      assert {:error, :receiver_does_not_exist} = ExBanking.send("from", "to2", 100.00, "EUR")
      assert current_balance_from == ExBanking.get_balance("from", "EUR")
    end
  end
end
