defmodule ExBanking do
  @moduledoc """
  Documentation for `ExBanking`.
  """

  require Logger

  alias ExBanking.Client
  alias ExBanking.UsersSupervisor

  defguardp is_positive_number(amount) when is_number(amount) and amount > 0.0

  @spec create_user(user :: String.t()) :: :ok | {:error, :wrong_arguments | :user_already_exists}
  @doc """
  - Function creates new user in the system
  - New user has zero balance of any currency

  - `user` - user name

  ## Examples

      iex> ExBanking.create_user("John")
      :ok

      iex(2)> ExBanking.create_user("John")
      {:error, :user_already_exists}

      iex(3)> ExBanking.create_user(["John"])
      {:error, :wrong_arguments}
  """
  def create_user(user) when is_binary(user) do
    if Client.exists?(user) do
      Logger.error("User #{user} already exists")

      {:error, :user_already_exists}
    else
      UsersSupervisor.start_child(user)
      :ok
    end
  end

  def create_user(_user) do
    Logger.error("Wrong arguments, user must be a string")

    {:error, :wrong_arguments}
  end

  @spec deposit(user :: String.t(), amount :: number, currency :: String.t()) ::
          {:ok, new_balance :: number}
          | {:error, :wrong_arguments | :user_does_not_exist | :too_many_requests_to_user}
  @doc """
  - Increases user’s balance in given currency by amount value
  - Returns new_balance of the user in given format
  """
  def deposit(user, amount, currency)
      when is_positive_number(amount) and is_binary(user) and is_binary(currency) do
    if Client.exists?(user) do
      Client.deposit(user, amount, currency)
    else
      {:error, :user_does_not_exist}
    end
  end

  def deposit(_user, _amount, _currency) do
    {:error, :wrong_arguments}
  end

  @spec withdraw(user :: String.t(), amount :: number, currency :: String.t()) ::
          {:ok, new_balance :: number}
          | {:error,
             :wrong_arguments
             | :user_does_not_exist
             | :not_enough_money
             | :too_many_requests_to_user}
  @doc """
   - Decreases user’s balance in given currency by amount value
   - Returns new_balance of the user in given format
  """
  def withdraw(user, amount, currency)
      when is_positive_number(amount) and is_binary(user) and is_binary(currency) do
    if Client.exists?(user) do
      Client.withdraw(user, amount, currency)
    else
      {:error, :user_does_not_exist}
    end
  end

  def withdraw(_user, _amount, _currency) do
    {:error, :wrong_arguments}
  end

  @spec get_balance(user :: String.t(), currency :: String.t()) ::
          {:ok, balance :: number}
          | {:error, :wrong_arguments | :user_does_not_exist | :too_many_requests_to_user}
  @doc """
   - Returns balance of the user in given format
  """
  def get_balance(user, currency) when is_binary(user) and is_binary(currency) do
    if Client.exists?(user) do
      Client.get_balance(user, currency)
    else
      {:error, :user_does_not_exist}
    end
  end

  @spec send(
          from_user :: String.t(),
          to_user :: String.t(),
          amount :: number,
          currency :: String.t()
        ) ::
          {:ok, from_user_balance :: number, to_user_balance :: number}
          | {:error,
             :wrong_arguments
             | :not_enough_money
             | :sender_does_not_exist
             | :receiver_does_not_exist
             | :too_many_requests_to_sender
             | :too_many_requests_to_receiver}
  @doc """
   - Decreases from_user’s balance in given currency by amount value
   - Increases to_user’s balance in given currency by amount value
   - Returns balance of from_user and to_user in given format
  """
  def send(from_user, to_user, amount, currency)
      when is_binary(from_user) and is_binary(to_user) and is_binary(currency) do
    with {:from, true} <- {:from, Client.exists?(from_user)},
         {:to, true} <- {:to, Client.exists?(to_user)} do
      Client.transfer(from_user, to_user, amount, currency)
    else
      {:from, false} -> {:error, :sender_does_not_exist}
      {:to, false} -> {:error, :receiver_does_not_exist}
    end
  end
end
