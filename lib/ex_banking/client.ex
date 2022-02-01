defmodule ExBanking.Client do
  @moduledoc """
  This module provides a client for the ExBanking service.
  """
  use GenServer

  require Logger

  @registry :currencies

  ## GenServer API

  def start_link(name) do
    data = %{name: name, balance: [Money.new(0)], transactions: :queue.new()}
    GenServer.start_link(__MODULE__, data, name: via_tuple(name))
  end

  def log_state(process_name) do
    process_name |> via_tuple() |> GenServer.call(:log_state)
  end

  @spec get_balance(String.t(), String.t()) :: number
  def get_balance(process_name, currency) do
    process_name |> via_tuple() |> GenServer.call({:get_balance, currency})
  end

  def transfer(process_name, to_user, amount, currency) when is_float(amount) do
    amount = amount |> Float.round(2) |> Kernel.*(100) |> trunc()
    transfer(process_name, to_user, amount, currency)
  end

  def transfer(process_name, to_user, amount, currency) do
    process_name |> via_tuple() |> GenServer.call({:transfer, to_user, amount, currency})
  end

  @spec deposit(String.t(), number, String.t()) :: number
  def deposit(process_name, amount, currency) when is_float(amount) do
    amount = amount |> Float.round(2) |> Kernel.*(100) |> trunc()
    deposit(process_name, amount, currency)
  end

  def deposit(process_name, amount, currency) do
    process_name |> via_tuple() |> GenServer.call({:deposit, amount, currency})
  end

  @spec withdraw(String.t(), number, String.t()) :: number
  def withdraw(process_name, amount, currency) when is_float(amount) do
    amount = amount |> Float.round(2) |> Kernel.*(100) |> trunc()
    withdraw(process_name, amount, currency)
  end

  def withdraw(process_name, amount, currency) do
    process_name |> via_tuple() |> GenServer.call({:withdraw, amount, currency})
  end

  @doc """
  This function will be called by the supervisor to retrieve the specification
  of the child process.The child process is configured to restart only if it
  terminates abnormally.
  """
  def child_spec(process_name) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [process_name]},
      restart: :transient
    }
  end

  def stop(process_name, stop_reason) do
    # Given the :transient option in the child spec, the GenServer will restart
    # if any reason other than `:normal` is given.
    process_name |> via_tuple() |> GenServer.stop(stop_reason)
  end

  ## GenServer Callbacks

  @impl true
  @spec init(any) :: {:ok, any}
  def init(args) do
    Logger.info("Creating currency to client #{args[:name]}")
    {:ok, args}
  end

  @impl true
  def handle_call(:log_state, _from, state) do
    {:reply, "State: #{inspect(state)}", state}
  end

  @impl true
  def handle_call({:transfer, to_user, amount, currency}, from, state) do
    Logger.warning(from == self())
    Logger.info("Verifying balance for #{state[:name]}")

    Logger.info("Balance for #{state[:name]}: #{print_money(state[:balance], currency)}")

    balance = decrease(state[:balance], amount, currency)

    if Money.negative?(balance) do
      Logger.error("Insufficient funds: #{Money.to_string(balance)}")

      {:reply, :not_enough_money, state}
    else
      Logger.info("New balance: #{Money.to_string(balance)}")
      Logger.info("Sending #{Money.to_string(Money.new(amount, currency))} to #{to_user}")

      to_user
      |> via_tuple()
      |> GenServer.whereis()
      |> send({:transfer, self(), amount, currency})

      receive do
        {:ok, to_balance} ->
          Logger.info("Transfer successful")

          {:reply, {:ok, money_to_float(balance), money_to_float(to_balance)},
           set_balance(state, balance, currency)}

        {:error, :not_enough_money} ->
          Logger.error("Transfer failed")
          {:reply, :not_enough_money, state}

        _ ->
          Logger.error("Transfer failed")
          {:reply, :failed, state}
      end
    end
  end

  @impl true
  def handle_call({:withdraw, amount, currency}, _from, state) do
    Logger.info(
      "Withdrawing #{Money.to_string(Money.new(amount, currency))} from #{print_money(state[:balance], currency)}"
    )

    balance = decrease(state[:balance], amount, currency)

    if Money.negative?(balance) do
      Logger.error("Insufficient funds: #{Money.to_string(balance)}")

      {:reply, :not_enough_money, state}
    else
      Logger.info("New balance: #{Money.to_string(balance)}")

      {:reply, money_to_float(balance), set_balance(state, balance, currency)}
    end
  end

  @impl true
  def handle_call({:deposit, amount, currency}, _from, state) do
    Logger.info(
      "Depositing #{Money.to_string(Money.new(amount, currency))} to #{print_money(state[:balance], currency)}"
    )

    balance = increase(state[:balance], amount, currency)

    Logger.info("New balance: #{Money.to_string(balance)}")

    {:reply, money_to_float(balance), set_balance(state, balance, currency)}
  end

  @impl true
  def handle_call({:get_balance, currency}, _from, state) do
    balance =
      state[:balance]
      |> do_get_balance(currency)
      |> money_to_float()

    {:reply, balance, state}
  end

  ###########################################################################

  @impl true
  def handle_info({:transfer, from, amount, currency}, state) do
    balance = increase(state[:balance], amount, currency)

    Logger.info(
      "Received #{Money.to_string(Money.new(amount, currency))} to #{Money.to_string(balance)}"
    )

    state = set_balance(state, balance, currency)
    Logger.info("Notifying origin...")
    send(from, {:ok, balance})

    {:noreply, state}
  rescue
    e ->
      Logger.error(Exception.format(:error, e, __STACKTRACE__))
      send(from, {:error, e})
      {:noreply, state}
  end

  ###########################################################################
  @spec exists?(any) :: boolean
  def exists?(name) do
    Registry.lookup(@registry, name)
    |> Enum.empty?()
    |> Kernel.!()
  end

  ## Private Functions
  defp set_balance(state, balance, currency) do
    new_balance =
      if balance.currency in Enum.map(state[:balance], fn %{currency: currency} -> currency end) do
        state[:balance]
        |> Enum.map(fn %{currency: cur} = current ->
          if to_string(cur) == String.upcase(currency) do
            balance
          else
            current
          end
        end)
      else
        state[:balance] ++ [balance]
      end

    %{state | balance: new_balance}
  end

  defp do_get_balance(balance, currency) do
    balance
    |> Enum.find(
      Money.new(0, currency),
      fn %{currency: cur} -> to_string(cur) == String.upcase(currency) end
    )
  end

  defp print_money(wallet, currency) do
    wallet
    |> do_get_balance(currency)
    |> Money.to_string()
  end

  defp decrease(balance, amount, currency) do
    balance
    |> do_get_balance(currency)
    |> Money.subtract(amount)
  end

  defp increase(balance, amount, currency) do
    balance
    |> do_get_balance(currency)
    |> Money.add(amount)
  end

  defp money_to_float(balance) do
    balance
    |> Money.to_decimal()
    |> Decimal.to_float()
  end

  defp via_tuple(name),
    do: {:via, Registry, {@registry, name}}
end
