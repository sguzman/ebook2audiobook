{
  description = "A reproducible development environment for the ebook2audiobook project.";

  # Nix flake inputs. These are the external dependencies of our flake.
  inputs = {
    # The primary source for Nix packages. We pin it to a specific revision for reproducibility.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # A utility library to easily generate flake outputs for different systems (linux, macos, etc.)
    flake-utils.url = "github:numtide/flake-utils";
  };

  # Nix flake outputs. This is what our flake provides to the user.
  outputs = { self, nixpkgs, flake-utils }:
    # This function creates outputs for each common system architecture.
    flake-utils.lib.eachDefaultSystem (system:
      let
        # Import the nixpkgs for the specific system.
        pkgs = import nixpkgs {
          inherit system;
          # Allow installation of unfree packages like NVIDIA drivers.
          # You must also add `accepted-unfree-packages = [ "nvidia-driver" ]` to your /etc/nix/nix.conf
          config.allowUnfree = true;
        };

        # List of system-level dependencies required by the project.
        # These are identified from the project's README file.
        systemDeps = with pkgs; [
          calibre             # For eBook conversion.
          ffmpeg-full         # For audio/video manipulation.
          nodejs              # A JavaScript runtime.
          mecab               # For Japanese text segmentation.
          mecab-ipadic        # Dictionary for mecab.
          espeak-ng           # Text-to-speech engine.
          rustc               # The Rust compiler.
          cargo               # The Rust package manager.
          sox                 # For sound processing.
        ];

        # List of Python dependencies from requirements.txt
        # We use the versions available in nixpkgs.
        pythonDeps = ps: with ps; [
          # Core ML and Data Science
          torch
          # Note: For GPU, torch is overridden below.
          numpy
          pandas
          scipy
          pillow
          
          # TTS and ASR
          coqui-tts           # CORRECTED: The Python package is named 'coqui-tts', not 'tts'.
          whisper             # OpenAI Whisper for ASR.

          # Web and API
          gradio
          requests
          beautifulsoup4
          
          # Utilities
          anyio
          charset-normalizer
          ebooklib
          einops
          encodec
          huggingface-hub
          inflect
          lxml
          pydantic
          pydub
          python-dotenv
          soupsieve
          tqdm
          transformers
          unidecode
          # Some packages might be missing from nixpkgs or need specific versions.
          # For those, you might need to use `buildPythonPackage` or other tools like poetry2nix.
        ];

        # Create a Python 3.12 environment with the specified packages.
        pythonEnv = pkgs.python312.withPackages pythonDeps;

        # --- GPU (CUDA) Specific Configuration ---
        # This section sets up the environment for NVIDIA GPUs.
        cudaPkgs = pkgs.cudaPackages_12; # Using CUDA Toolkit 12

        # Create a PyTorch overlay that uses CUDA.
        # This ensures that PyTorch can access the GPU.
        pkgs-cuda = pkgs.extend (self: super: {
          python3 = super.python3.override {
            packageOverrides = python-self: python-super: {
              pytorch-bin = cudaPkgs.pytorch;
              # You may need to add other CUDA-enabled python packages here
              # e.g., torchaudio, torchvision if they have cuda variants in nixpkgs
            };
          };
        });
        
        pythonEnv-cuda = pkgs-cuda.python312.withPackages pythonDeps;


      in
      {
        # Development shells that can be activated with `nix develop`
        devShells = {
          # Default shell for CPU-only execution
          # To use: `nix develop`
          default = pkgs.mkShell {
            name = "ebook2audiobook-cpu";
            buildInputs = [ pythonEnv ] ++ systemDeps;

            shellHook = ''
              echo "--- Ebook2Audiobook CPU Environment ---"
              echo "Welcome! All dependencies are now in your PATH."
              echo "Run the application with: python app.py"
            '';
          };

          # A separate shell for GPU (NVIDIA CUDA) execution
          # To use: `nix develop .#gpu`
          gpu = pkgs.mkShell {
            name = "ebook2audiobook-gpu";
            # Includes Python with CUDA-enabled PyTorch and system dependencies
            buildInputs = [ pythonEnv-cuda ] ++ systemDeps ++ [
              # Add CUDA specific libraries and drivers
              cudaPkgs.cudatoolkit
              cudaPkgs.cudnn
              cudaPkgs.nccl
              pkgs.nvidia-driver # Make sure this matches your system's driver
            ];

            # Set environment variables required for CUDA libraries to be found
            shellHook = ''
              echo "--- Ebook2Audiobook GPU Environment ---"
              echo "CUDA Toolkit and NVIDIA drivers are available."
              echo "Run the application with: python app.py --device gpu"
              export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath (with cudaPkgs; [ cudatoolkit cudnn nccl ])}:${pkgs.nvidia-driver}/lib"
              export XLA_FLAGS=--xla_gpu_cuda_data_dir="${cudaPkgs.cudatoolkit}"
            '';
          };
        };
      });
}
