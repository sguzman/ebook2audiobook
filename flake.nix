{
  description = "A reproducible development environment for the ebook2audiobook project.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        # --- Custom Python Packages ---
        # Only define packages that are truly missing from nixpkgs.
        # Since sudachipy is likely fixed, we no longer need to define it here.

        m4b-util = pkgs.python3Packages.buildPythonPackage rec {
          pname = "m4b-util";
          version = "2025.4.16";
          format = "pyproject";
          src = pkgs.fetchPypi {
            inherit pname version;
            hash = "sha256-RkX1Y6V1rYF+Hn71B8X3Z3XjK2n4k6iN9w8Z3p8Hn4g=";
          };
          propagatedBuildInputs = with pkgs.python3Packages; [ lark natsort rich poetry-core ];
          doCheck = false;
        };
        
        translate-pkg = pkgs.python3Packages.buildPythonPackage rec {
          pname = "translate";
          version = "3.6.1";
          format = "setuptools";
          src = pkgs.fetchPypi {
            inherit pname version;
            sha256 = "7e70ffa46f193cc744be7c88b8e1323f10f6b2bb90d24bb5d29fdf1e56618783";
          };
          nativeBuildInputs = with pkgs.python3Packages; [ setuptools pip wheel ];
          propagatedBuildInputs = with pkgs.python3Packages; [ six ];
          doCheck = false;
        };

        suno-bark-pkg = pkgs.python3Packages.buildPythonPackage rec {
          pname = "suno-bark";
          version = "1.0.1";
          format = "pyproject";
          src = pkgs.fetchPypi {
            inherit pname version;
            sha256 = "sha256-gZ22oP9wG+3+Qj0iB/K9o3wz0f1i8n9t7X6yP5aQ0cE=";
          };
          propagatedBuildInputs = with pkgs.python3Packages; [ numpy scipy tokenizers torch transformers encodec huggingface-hub ];
          doCheck = false;
        };

        systemDeps = with pkgs; [
          calibre ffmpeg-full nodejs mecab espeak-ng rustc cargo sox tts
        ];

        # List of all Python dependencies for the environment.
        pythonDeps = ps: with ps; [
          # Core application dependencies
          torch numpy pandas scipy pillow whisper gradio requests beautifulsoup4
          anyio charset-normalizer ebooklib einops encodec huggingface-hub inflect
          lxml pydantic pydub python-dotenv soupsieve tqdm transformers pyopengl
          unidecode ray rich
          # Dependencies that were broken/missing in nixpkgs
          pynvml sudachidict-core unidic-lite
          # Use the version of sudachipy from nixpkgs, which should be fixed.
          sudachipy
          # Custom-packaged dependencies
          m4b-util translate-pkg suno-bark-pkg
        ];

        pythonEnv = pkgs.python312.withPackages pythonDeps;

        # --- GPU (CUDA) Specific Configuration ---
        cudaPkgs = pkgs.cudaPackages_12;
        cuda-overlay = final: prev: {
          python3 = prev.python3.override {
            packageOverrides = python-self: python-super: {
              torch = cudaPkgs.pytorch;
              torchvision = cudaPkgs.torchvision;
            };
          };
        };
        pkgs-cuda = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [ cuda-overlay ];
        };
        pythonEnv-cuda = pkgs-cuda.python312.withPackages pythonDeps;

      in
      {
        devShells = {
          default = pkgs.mkShell {
            name = "ebook2audiobook-cpu";
            buildInputs = [ pythonEnv ] ++ systemDeps;
            shellHook = ''
              echo "--- Ebook2Audiobook CPU Environment ---"
              echo "All dependencies are provided by Nix."
              echo "Run the application directly with: python app.py"
            '';
          };

          gpu = pkgs.mkShell {
            name = "ebook2audiobook-gpu";
            buildInputs = [ pythonEnv-cuda ] ++ systemDeps ++ [
              cudaPkgs.cudatoolkit
              cudaPkgs.cudnn
              cudaPkgs.nccl
            ];
            shellHook = ''
              echo "--- Ebook2Audiobook GPU Environment ---"
              echo "CUDA Toolkit and NVIDIA drivers are available."
              echo "All dependencies are provided by Nix."
              echo "Run the application directly with: python app.py --device gpu"
              export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath (with cudaPkgs; [ cudatoolkit cudnn nccl ])}:${pkgs.stdenv.cc.cc.lib}/lib"
              export XLA_FLAGS=--xla_gpu_cuda_data_dir="${cudaPkgs.cudatoolkit}"
            '';
          };
        };
      });
}

