defmodule ExBanking.Client do
  @moduledoc """
  This module provides a client for the ExBanking service.
  """
  use GenServer

  require Logger

  @registry :currencies
  @requests_size_limit 10

  ## GenServer API

  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(name) do
    data = %{
      name: name,
      balance: [Money.new(0)],
      request_queue_size: 0
    }

    GenServer.start_link(__MODULE__, data, name: via_tuple(name))
  end

  def make_request({_function, [process_name | _args]} = request_handler, from) do
    process_name |> via_tuple() |> GenServer.cast({:enqueue_request, request_handler, from})
  end

  @spec log_state(any) :: any
  def log_state(process_name) do
    process_name |> via_tuple() |> GenServer.call(:log_state)
  end

  @spec get_balance(String.t(), String.t()) :: number
  def get_balance(process_name, currency) do
    process_name |> via_tuple() |> GenServer.call({:get_balance, currency})
  end

  @spec transfer(any, any, any, any) :: any
  def transfer(process_name, to_user, amount, currency) do
    process_name |> via_tuple() |> GenServer.call({:transfer, to_user, amount, currency})
  end

  @spec deposit(String.t(), number, String.t()) :: number
  def deposit(process_name, amount, currency) do
    {:ok, amount} = Money.parse(amount, currency)
    process_name |> via_tuple() |> GenServer.call({:deposit, amount, currency})
  end

  @spec withdraw(String.t(), number, String.t()) :: number
  def withdraw(process_name, amount, currency) do
    {:ok, amount} = Money.parse(amount, currency)
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
    {:reply, "State: #{inspect(state)}",
     %{state | request_queue_size: state.request_queue_size - 1}}
  end

  @impl true
  def handle_call({:transfer, to_user, amount, currency}, _from, state) do
    Logger.info("Verifying balance for #{state[:name]}")

    Logger.info("Balance for #{state[:name]}: #{print_money(state[:balance], currency)}")
    value = Money.parse!(amount, currency)
    balance = decrease(state[:balance], value, currency)

    if Money.negative?(balance) do
      Logger.error("Insufficient funds: #{Money.to_string(balance)}")

      {:reply, :not_enough_money, %{state | request_queue_size: state.request_queue_size - 1}}
    else
      Logger.info("New balance: #{Money.to_string(balance)}")
      Logger.info("Sending #{Money.to_string(value)} to #{to_user}")

      make_request({:deposit, [to_user, amount, currency]}, self())

      receive do
        to_balance when is_float(to_balance) ->
          Logger.info("Transfer successful")
          state = set_balance(state, balance, currency)

          {:reply, {:ok, money_to_float(balance), to_balance},
           %{state | request_queue_size: state.request_queue_size - 1}}

        :too_many_requests_to_user ->
          Logger.error("Transfer failed due to too many requests to #{to_user}")

          {:reply, :too_many_requests_to_receiver,
           %{state | request_queue_size: state.request_queue_size - 1}}

        {:error, :not_enough_money} ->
          Logger.error("Transfer failed")
          {:reply, :not_enough_money, %{state | request_queue_size: state.request_queue_size - 1}}

        {ref, :ok} ->
          Logger.info("Transfer successful? #{inspect(ref)}")
          state = set_balance(state, balance, currency)

          {:reply, {:ok, money_to_float(balance), 0},
           %{state | request_queue_size: state.request_queue_size - 1}}

        error ->
          Logger.error("Transfer failed due to error: #{inspect(error)}")
          {:reply, :failed, %{state | request_queue_size: state.request_queue_size - 1}}
      after
        60_000 ->
          Logger.error("Transfer failed due to timeout")
          {:reply, :timeout, %{state | request_queue_size: state.request_queue_size - 1}}
      end
    end
  end

  @impl true
  def handle_call({:withdraw, amount, currency}, _from, state) do
    Logger.info(
      "Withdrawing #{Money.to_string(amount)} from #{print_money(state[:balance], currency)}"
    )

    balance = decrease(state[:balance], amount, currency)

    if Money.negative?(balance) do
      Logger.error("Insufficient funds: #{Money.to_string(balance)}")

      {:reply, :not_enough_money, %{state | request_queue_size: state.request_queue_size - 1}}
    else
      Logger.info("New balance: #{Money.to_string(balance)}")
      state = set_balance(state, balance, currency)

      {:reply, money_to_float(balance),
       %{state | request_queue_size: state.request_queue_size - 1}}
    end
  end

  @impl true
  def handle_call({:deposit, amount, currency}, _from, state) do
    Logger.info(
      "Depositing #{Money.to_string(amount)} to #{print_money(state[:balance], currency)}"
    )

    balance = increase(state[:balance], amount, currency)

    Logger.info("New balance: #{Money.to_string(balance)}")
    state = set_balance(state, balance, currency)

    {:reply, money_to_float(balance), %{state | request_queue_size: state.request_queue_size - 1}}
  rescue
    e ->
      Logger.error("Deposit failed: #{inspect(e)}")
      {:reply, :failed, %{state | request_queue_size: state.request_queue_size - 1}}
  end

  @impl true
  def handle_call({:get_balance, currency}, _from, state) do
    balance =
      state[:balance]
      |> do_get_balance(currency)
      |> money_to_float()

    {:reply, balance, %{state | request_queue_size: state.request_queue_size - 1}}
  end

  # ---------------- Server Callbacks ----------------

  @impl true
  # No tokens available...enqueue the request
  def handle_cast(
        {:enqueue_request, _request_handler, from},
        %{request_queue_size: queue_size} = state
      )
      when queue_size >= @requests_size_limit do
    Logger.error("Too many requests - #{from}")
    send(from, :too_many_requests_to_user)

    {:noreply, state}
  end

  def handle_cast({:enqueue_request, request_handler, from}, state) do
    async_task_request(request_handler, from)
    {:noreply, %{state | request_queue_size: state.request_queue_size + 1}}
  end

  @impl true
  def handle_info({ref, _result}, state) do
    Process.demonitor(ref, [:flush])

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  def handle_info(wtf, state) do
    Logger.error("Unknown info: #{inspect(wtf)}")
    {:noreply, state}
  end

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

  defp async_task_request(request_handler, from) do
    start_message = "Request started #{NaiveDateTime.utc_now()}"
    Logger.info(start_message)

    Task.Supervisor.async_nolink(RateLimiter.TaskSupervisor, fn ->
      {req_function, req_args} = request_handler

      response = apply(__MODULE__, req_function, req_args)
      send(from, response)

      Logger.info("Request completed #{NaiveDateTime.utc_now()}")
    end)
  end
end
