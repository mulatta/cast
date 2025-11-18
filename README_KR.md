# CAST: Content-Addressed Storage Tool

재현 가능성과 버전 관리를 갖춘 대규모 과학 데이터베이스 관리를 위한 Nix 통합 콘텐츠 주소 지정 저장소 시스템

## 개요

CAST는 재현 가능한 과학 워크플로우에서 대용량 생물학 데이터베이스(NCBI, UniProt, Pfam 등)를 관리하는 문제를 해결합니다:

- **문제**: 수 기가바이트 규모의 데이터베이스는 적절한 버전 관리가 부족하며, `/nix/store`에 저장하는 것은 비실용적입니다
- **해결책**: 데이터를 위한 콘텐츠 주소 지정 저장소(CAS) + 메타데이터를 위한 Nix 파생(derivation) = 재현 가능한 데이터베이스 관리

### 주요 기능

- **순수 설정(Pure Configuration)**: 환경 변수 불필요, 모든 설정은 Nix에서
- **콘텐츠 주소 지정 저장소**: BLAKE3 기반 중복 제거 및 무결성 검증
- **Nix 통합**: 완전한 의존성 추적을 갖춘 Nix flake 입력으로서의 데이터베이스
- **변환 파이프라인**: 출처 추적을 통한 재현 가능한 데이터 변환
- **버전 관리**: 쉬운 버전 고정이 가능한 다중 버전 데이터베이스 레지스트리
- **공간 효율성**: 데이터셋 버전 간 중복 제거
- **타입 안전성**: Nix 평가 시점에 모든 설정 검증

## 빠른 시작

### 설치

flake 입력으로 CAST를 추가합니다:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    cast.url = "github:yourusername/cast";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # CAST 설정은 아래 "기본 사용법" 참조
    };
}
```

**참고**: CAST는 flake-parts를 사용하여 깔끔한 설정을 제공합니다.

CLI 도구 빌드:

```bash
nix build github:yourusername/cast#cast-cli
./result/bin/cast --version
```

### 기본 사용법

1. **CAST flakeModule import 및 설정**:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    cast.url = "github:yourusername/cast";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      # CAST flakeModule import
      imports = [ inputs.cast.flakeModules.default ];

      perSystem = { castLib, ... }: {
        # CAST 저장소 경로 설정
        cast.storePath = "/data/lab-databases";

        # castLib이 자동으로 주입되어 사용 가능
        packages.my-dataset = castLib.mkDataset {
          name = "my-dataset";
          version = "1.0.0";
          manifest = ./my-dataset-manifest.json;
        };
      };
    };
}
```

**핵심 포인트**:
- `imports = [ inputs.cast.flakeModules.default ]` - CAST 모듈 활성화
- `cast.storePath` - 데이터 저장 위치 설정
- `castLib` - perSystem에 자동 주입됨 (별도 설정 불필요)

2. **데이터셋 매니페스트 생성** (`my-dataset-manifest.json`):

```json
{
  "schema_version": "1.0",
  "dataset": {
    "name": "my-dataset",
    "version": "1.0.0",
    "description": "예제 데이터셋"
  },
  "source": {
    "url": "https://example.com/data.tar.gz",
    "archive_hash": "blake3:..."
  },
  "contents": [
    {
      "path": "data.txt",
      "hash": "blake3:...",
      "size": 12345,
      "executable": false
    }
  ],
  "transformations": []
}
```

3. **빌드 및 사용**:

```bash
# 데이터셋 빌드 (순수 평가!)
nix build .#my-dataset

# 파일은 심볼릭 링크로 사용 가능
ls -la result/data/
cat result/data/data.txt
```

## 아키텍처

```
┌─────────────────────────────────────┐
│ 사용자 프로젝트                      │
│  - Flake 입력 (데이터베이스 의존성) │
│  - flakeModules import               │
│  - 순수 설정 (cast.storePath)       │
└─────────────────────────────────────┘
                ↓
┌─────────────────────────────────────┐
│ CAST 라이브러리 (lib/*.nix)         │
│  - flake-module.nix (자동 주입)     │
│  - mkDataset                         │
│  - transform                         │
│  - fetchDatabase (향후)             │
└─────────────────────────────────────┘
                ↓
┌──────────────────┬──────────────────┐
│ 메타데이터       │ CLI 도구         │
│ (/nix/store)     │ (cast-cli)       │
│                  │                  │
│ - manifest.json  │ - put/get        │
│ - symlink farms  │ - transform      │
│ - derivations    │ - hashing        │
└──────────────────┴──────────────────┘
                ↓
┌─────────────────────────────────────┐
│ CAS 백엔드 (설정된 storePath)        │
│                                      │
│ store/{hash[:2]}/{hash[2:4]}/{hash} │
│ - 실제 파일 내용                     │
│ - BLAKE3 주소 지정                   │
│ - 중복 제거됨                        │
└─────────────────────────────────────┘
```

### 데이터 흐름

1. **파일** → `cast put` → **CAST 저장소** (콘텐츠 주소 지정)
2. **매니페스트** + **설정** → `castLib.mkDataset` → **Nix derivation** (순수)
3. **원본 데이터셋** → `castLib.transform` → **변환된 데이터셋** (출처 포함)

## API 참조

### CAST flakeModule 설정

CAST는 flake-parts 모듈을 제공하여 자동 설정 및 `castLib` 주입을 지원합니다.

**기본 설정**:

```nix
{
  imports = [ inputs.cast.flakeModules.default ];

  perSystem = { castLib, ... }: {
    # CAST 저장소 경로 설정
    cast.storePath = "/data/cast-store";

    # castLib이 자동으로 주입되어 사용 가능
    packages.my-db = castLib.mkDataset {...};
  };
}
```

**설정 옵션**:
- `cast.storePath` (경로, 필수): CAST 저장소 디렉토리 경로

**자동 제공**:
- `castLib` - perSystem에 자동 주입되는 설정된 라이브러리 인스턴스

**시스템별 설정 예제**:

```nix
{
  imports = [ inputs.cast.flakeModules.default ];

  perSystem = { system, castLib, ... }: {
    # 시스템별로 다른 저장소 경로 사용
    cast.storePath =
      if system == "x86_64-linux"
      then "/fast/nvme/cast"    # SSD
      else "/bulk/hdd/cast";    # HDD

    packages = {
      ncbi-nr = castLib.mkDataset {...};
      uniprot = castLib.mkDataset {...};
    };
  };
}
```

**환경 변수 기반 설정**:

```nix
perSystem = { castLib, ... }: {
  cast.storePath = builtins.getEnv "HOME" + "/.cache/cast";

  packages.my-db = castLib.mkDataset {...};
}
```

### `castLib.mkDataset`

매니페스트로부터 데이터셋 derivation을 생성합니다.

```nix
castLib.mkDataset {
  name = "dataset-name";
  version = "1.0.0";
  manifest = ./manifest.json;  # 또는 속성 집합
  storePath = null;  # 선택사항: 설정된 storePath 재정의
}
```

**매개변수**:
- `name` (문자열): 데이터셋 이름 (환경 변수에 사용됨)
- `version` (문자열): 데이터셋 버전
- `manifest` (경로 또는 속성집합): 데이터셋 매니페스트
- `storePath` (문자열, 선택사항): 설정된 저장소 경로 재정의

**반환값**: 다음을 포함하는 Nix derivation:
- `/data/` - CAST 저장소의 파일에 대한 심볼릭 링크
- `/manifest.json` - 데이터셋 매니페스트
- 환경 변수: `$CAST_DATASET_<NAME>`, `$CAST_DATASET_<NAME>_VERSION`

**예제**:

```nix
{
  imports = [ inputs.cast.flakeModules.default ];

  perSystem = { castLib, pkgs, config, ... }: {
    cast.storePath = "/data/cast";

    packages.ncbi-nr = castLib.mkDataset {
      name = "ncbi-nr";
      version = "2024-01-15";
      manifest = ./ncbi-nr-manifest.json;
    };

    devShells.default = pkgs.mkShell {
      buildInputs = [ config.packages.ncbi-nr ];
      # $CAST_DATASET_NCBI_NR이 이제 데이터셋을 가리킴
    };
  };
}
```

### `castLib.transform`

빌더 스크립트로 데이터셋을 변환합니다.

```nix
castLib.transform {
  name = "transformation-name";
  src = sourceDataset;  # 입력 데이터셋
  builder = ''
    # 다음에 접근 가능한 Bash 스크립트:
    # $SOURCE_DATA - 입력 파일
    # $CAST_OUTPUT - 출력 디렉토리

    process-data "$SOURCE_DATA"/* > "$CAST_OUTPUT/result.txt"
  '';
  params = {};  # 선택사항: 변환 매개변수
}
```

**매개변수**:
- `name` (문자열): 변환 이름
- `src` (derivation): 원본 데이터셋
- `builder` (문자열): 변환을 위한 Bash 스크립트
- `params` (속성집합, 선택사항): 변환 매개변수 (JSON으로 전달됨)

**반환값**: 변환된 데이터와 출처 체인을 포함한 데이터셋 derivation.

**예제 - FASTA를 MMseqs2로 변환**:

```nix
{
  imports = [ inputs.cast.flakeModules.default ];

  perSystem = { castLib, pkgs, config, ... }: {
    cast.storePath = "/data/cast";

    packages = {
      raw-fasta = castLib.mkDataset {...};

      mmseqs-db = castLib.transform {
        name = "to-mmseqs";
        src = config.packages.raw-fasta;

        builder = ''
          ${pkgs.mmseqs2}/bin/mmseqs createdb \
            "$SOURCE_DATA/sequences.fasta" \
            "$CAST_OUTPUT/mmseqs_db"
        '';
      };
    };
  };
}
```

### `cast.lib.symlinkSubset`

선택된 파일로 데이터셋의 부분 집합을 생성합니다.

```nix
cast.lib.symlinkSubset {
  name = "subset-name";
  paths = [
    { name = "ncbi"; path = datasets.ncbi-nr; }
    { name = "uniprot"; path = datasets.uniprot; }
  ];
}
```

### `cast.lib.fetchDatabase` (향후)

데이터베이스를 다운로드하고 등록합니다.

```nix
castLib.fetchDatabase {
  name = "ncbi-nr";
  url = "ftp://ftp.ncbi.nlm.nih.gov/blast/db/nr.tar.gz";
  hash = "blake3:...";  # 선택사항: 검증용
  extract = true;
}
```

## 예제

### 간단한 데이터셋

샘플 데이터 파일이 포함된 기본 예제는 [`examples/simple-dataset/`](examples/simple-dataset/)를 참조하세요.

```bash
cd examples/simple-dataset
nix build .#example-dataset  # 순수 평가!
```

**핵심 패턴**:
```nix
{
  imports = [ inputs.cast.flakeModules.default ];

  perSystem = { castLib, ... }: {
    cast.storePath = builtins.getEnv "HOME" + "/.cache/cast";

    packages.example-dataset = castLib.mkDataset {
      name = "simple-example";
      version = "1.0.0";
      manifest = ./manifest.json;
    };
  };
}
```

### 변환

변환 파이프라인 예제는 [`examples/transformation/`](examples/transformation/)를 참조하세요:

- 파일 복사 변환
- 텍스트 처리 (대문자 변환)
- 출처가 포함된 체인 변환

```bash
cd examples/transformation
nix build .#example-chain
cat result/manifest.json | jq '.transformations'
```

### 다중 버전 데이터베이스 레지스트리

다중 버전 데이터베이스 관리는 [`examples/registry/`](examples/registry/)를 참조하세요:

```nix
{
  imports = [ inputs.cast.flakeModules.default ];

  perSystem = { castLib, ... }: {
    cast.storePath = builtins.getEnv "HOME" + "/.cache/cast";

    packages = let
      test-db-versions = {
        "test-db-1.0.0" = castLib.mkDataset {
          name = "test-db";
          version = "1.0.0";
          manifest = ./manifests/test-db-1.0.0.json;
        };
        "test-db-1.1.0" = castLib.mkDataset {
          name = "test-db";
          version = "1.1.0";
          manifest = ./manifests/test-db-1.1.0.json;
        };
        "test-db-2.0.0" = castLib.mkDataset {
          name = "test-db";
          version = "2.0.0";
          manifest = ./manifests/test-db-2.0.0.json;
        };
      };
    in
      test-db-versions // {
        # 편의를 위한 별칭
        test-db-latest = test-db-versions."test-db-2.0.0";
        test-db-stable = test-db-versions."test-db-1.1.0";
      };
  };
}
```

```bash
cd examples/registry
nix build .#test-db-latest
nix develop .#legacy  # 이전 버전 사용
```

### flake-parts를 사용한 프로덕션 데이터베이스 레지스트리

프로덕션 준비 패턴은 [`examples/database-registry/`](examples/database-registry/)를 참조하세요:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    cast.url = "github:yourusername/cast";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = import inputs.systems;

      # CAST flakeModule import
      imports = [ inputs.cast.flakeModules.default ];

      perSystem = { config, castLib, ... }: {
        # CAST 저장소 경로 설정
        cast.storePath = "/data/lab-databases";

        packages = {
          ncbi-nr = castLib.mkDataset {
            name = "ncbi-nr";
            version = "2024-01-15";
            manifest = ./manifests/ncbi-nr.json;
          };

          uniprot = castLib.mkDataset {
            name = "uniprot";
            version = "2024-01";
            manifest = ./manifests/uniprot.json;
          };

          # 변환
          ncbi-nr-mmseqs = castLib.transform {
            name = "ncbi-nr-mmseqs";
            src = config.packages.ncbi-nr;
            builder = pkgs.writeShellScript "to-mmseqs" ''
              ${pkgs.mmseqs2}/bin/mmseqs createdb \
                "$SOURCE_DATA/nr.fasta" \
                "$CAST_OUTPUT/nr_mmseqs"
            '';
          };
        };
      };
    };
}
```

## CLI 참조

### `cast put`

파일을 CAST에 저장하고 해시를 반환합니다:

```bash
cast put /path/to/file
# 출력: blake3:abc123...
```

### `cast get`

해시로 파일 경로를 검색합니다:

```bash
cast get blake3:abc123...
# 출력: /data/cast-store/store/ab/c1/abc123...
```

### `cast transform`

변환 매니페스트를 생성합니다 (`castLib.transform`에서 사용):

```bash
cast transform \
  --input-manifest source-manifest.json \
  --output-dir ./output \
  --transform-type my-transform
```

## 설정

자세한 설정 가이드는 [`CONFIGURATION.md`](CONFIGURATION.md)를 참조하세요.

### 빠른 참조

**CAST flakeModule 설정 패턴** (권장):

```nix
{
  imports = [ inputs.cast.flakeModules.default ];

  perSystem = { castLib, ... }: {
    # CAST 저장소 경로 설정
    cast.storePath = "/data/cast-store";

    # castLib이 자동으로 주입되어 사용 가능
    packages.my-db = castLib.mkDataset {...};
  };
}
```

**설정 우선순위**:

1. `mkDataset`의 명시적 `storePath` 매개변수
2. `cast.storePath`에 설정된 경로
3. 도움말 메시지와 함께 오류 (암묵적 기본값 없음)

**데이터셋을 위한 환경 변수** (자동 생성):

- `CAST_DATASET_<NAME>` - 데이터셋 `/data` 디렉토리 경로
- `CAST_DATASET_<NAME>_VERSION` - 데이터셋 버전
- `CAST_DATASET_<NAME>_MANIFEST` - 매니페스트 경로

## 사용 사례

### 생물정보학 파이프라인

```nix
{
  inputs.databases.url = "git+ssh://lab-server/databases";

  outputs = { self, nixpkgs, databases }: {
    packages.x86_64-linux.analysis = pkgs.mkDerivation {
      name = "protein-analysis";
      buildInputs = [
        databases.packages.x86_64-linux.ncbi-nr
        databases.packages.x86_64-linux.uniprot
        pkgs.mmseqs2
      ];

      buildPhase = ''
        mmseqs search \
          query.fasta \
          "$CAST_DATASET_NCBI_NR/nr" \
          results.tsv
      '';
    };
  };
}
```

### 재현 가능한 연구

```nix
# 재현성을 위해 정확한 데이터베이스 버전 고정
{
  packages.analysis-v1 = mkAnalysis {
    databases = {
      ncbi = dbs.ncbi-nr."2024-01-15";  # 특정 버전
      uniprot = dbs.uniprot."2024.01";
    };
  };
}
```

### 데이터베이스 변환

```nix
{
  imports = [ inputs.cast.flakeModules.default ];

  perSystem = { castLib, pkgs, config, ... }: {
    cast.storePath = "/data/cast";

    packages = {
      # 원본 FASTA 데이터베이스
      ncbi-raw = castLib.mkDataset {
        name = "ncbi-nr";
        version = "2024-01-15";
        manifest = ./ncbi-nr.json;
      };

      # MMseqs 형식으로 변환
      ncbi-mmseqs = castLib.transform {
        name = "ncbi-to-mmseqs";
        src = config.packages.ncbi-raw;
        builder = ''
          ${pkgs.mmseqs2}/bin/mmseqs createdb \
            "$SOURCE_DATA/nr.fasta" \
            "$CAST_OUTPUT/nr_mmseqs"
        '';
      };

      # BLAST 형식으로 변환
      ncbi-blast = castLib.transform {
        name = "ncbi-to-blast";
        src = config.packages.ncbi-raw;
        builder = ''
          ${pkgs.blast}/bin/makeblastdb \
            -in "$SOURCE_DATA/nr.fasta" \
            -dbtype prot \
            -out "$CAST_OUTPUT/nr_blast"
        '';
      };
    };
  };
}
```

## 설계 결정

자세한 아키텍처 결정은 [`CLAUDE.md`](CLAUDE.md)를 참조하세요:

- 해싱에 BLAKE3를 사용하는 이유
- 데이터와 메타데이터를 분리하는 이유
- 순수 설정을 사용하는 이유 (환경 변수 없음)
- 저장소 형식의 근거
- Nix 통합 이유

## 개발

### 프로젝트 구조

```
cast/
├── lib/                  # Nix 라이브러리 함수
│   ├── default.nix       # 주요 내보내기
│   ├── flake-module.nix  # flake-parts 모듈 (권장)
│   ├── mkDataset.nix
│   ├── transform.nix
│   ├── manifest.nix
│   └── types.nix
├── packages/
│   └── cast-cli/        # Rust CLI 도구
├── examples/            # 사용 예제
│   ├── simple-dataset/
│   ├── transformation/
│   ├── registry/
│   └── database-registry/
└── schemas/             # JSON 스키마
    └── manifest-v1.json
```

### 소스에서 빌드

```bash
# 저장소 복제
git clone https://github.com/yourusername/cast
cd cast

# CLI 도구 빌드
nix build .#cast-cli

# 모든 테스트 실행
nix flake check

# Rust 도구가 포함된 개발 셸
nix develop
```

### 테스트 실행

```bash
# Nix 라이브러리 테스트
nix build .#checks.x86_64-linux.lib-validators
nix build .#checks.x86_64-linux.integration-mkDataset-attrset

# Rust 테스트
cd packages/cast-cli
cargo test

# 코드 포맷팅
nix fmt
```

## 로드맵

### 1단계: MVP ✅
- [x] 핵심 라이브러리 함수 (`mkDataset`, `transform`)
- [x] BLAKE3 해싱
- [x] 로컬 저장소 백엔드
- [x] 기본 CLI (`put`, `get`, `transform`)
- [x] 변환 출처 추적

### 2단계: flakeModules 패턴 ✅
- [x] flake-parts 기반 flakeModules 패턴
- [x] 자동 castLib 주입 (perSystem)
- [x] 환경 변수 불필요
- [x] 타입 검사된 설정 (cast.storePath)
- [x] Nix 패키지로서의 cast-cli
- [x] 완전한 데이터베이스 레지스트리 예제
- [x] `nix build --pure`와 호환

### 3단계: 데이터베이스 관리 (진행 중)
- [ ] 일반 변환 빌더 (`toMMseqs`, `toBLAST`, `toDiamond`)
- [ ] 시스템 전체 데이터베이스 관리를 위한 NixOS 모듈
- [ ] 포괄적인 문서화

### 4단계: 고급 기능 (향후)
- [ ] `fetchDatabase` 구현
- [ ] 자동 매니페스트 생성
- [ ] 가비지 컬렉션
- [ ] 다중 계층 저장소 (SSD/HDD)
- [ ] 원격 저장소 백엔드
- [ ] 데이터셋 브라우징을 위한 웹 UI

## 기여

기여를 환영합니다! 다음을 따라주세요:

1. Nix 코드 스타일 규칙 준수
2. 새로운 기능에 대한 테스트 추가
3. 문서 업데이트
4. 커밋 전 `nix fmt` 실행
5. 순수 설정 패턴 사용 (환경 변수 없음)

## 라이선스

[라이선스 미정]

## 인용

연구에서 CAST를 사용하는 경우 다음과 같이 인용해주세요:

```
[인용 미정]
```

## 관련 프로젝트

- [Nix](https://nixos.org/) - 재현 가능한 패키지 관리
- [IPFS](https://ipfs.io/) - 콘텐츠 주소 지정 저장소
- [Git LFS](https://git-lfs.github.com/) - Git을 위한 대용량 파일 저장소
- [Bazel](https://bazel.build/) - 콘텐츠 주소 지정이 있는 빌드 시스템

## 연락처

- 이슈: https://github.com/yourusername/cast/issues
- 토론: https://github.com/yourusername/cast/discussions

---

재현 가능한 과학을 위해 ❤️로 만들어졌습니다
