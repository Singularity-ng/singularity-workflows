  @doc """
  Save model checkpoint
  """
  def save_checkpoint(trainer, checkpoint_name) do
    Logger.info("Saving checkpoint: #{checkpoint_name}")

    checkpoint_dir = Path.join(models_dir(), "#{trainer.model}-#{checkpoint_name}")
    File.mkdir_p!(checkpoint_dir)

    # Save actual model weights and configuration
    config = %{
      "model" => "#{trainer.model}",
      "checkpoint" => checkpoint_name,
      "saved_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "training_config" => trainer.training_config,
      "embedding_dim" => trainer.embedding_dim,
      "vocab_size" => trainer.vocab_size
    }

    # Save configuration
    File.write!(Path.join(checkpoint_dir, "config.json"), Jason.encode!(config, pretty: true))
    
    # Save model parameters
    save_model_weights(trainer, checkpoint_dir)
    
    # Save tokenizer if available
    save_tokenizer(trainer, checkpoint_dir)
    
    # Save training state
    save_training_state(trainer, checkpoint_dir)

    {:ok, checkpoint_dir}
  end

  defp load_checkpoint_data(trainer, checkpoint_dir) do
    # Load checkpoint data from files
    try do
      # Load configuration
      config_file = Path.join(checkpoint_dir, "config.json")
      config = File.read!(config_file) |> Jason.decode!()
      
      # Load model weights
      weights_file = Path.join(checkpoint_dir, "weights.bin")
      weights_data = File.read!(weights_file) |> :erlang.binary_to_term()
      
      # Load training state
      state_file = Path.join(checkpoint_dir, "training_state.json")
      training_state = File.read!(state_file) |> Jason.decode!()
      
      {:ok, config, weights_data, training_state}
    rescue
      error -> {:error, "Failed to load checkpoint data: #{inspect(error)}"}
    end
  end