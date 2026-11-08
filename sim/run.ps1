param([string]$SimulatorBin = '')
$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path $PSScriptRoot -Parent
$buildPath = Join-Path $PSScriptRoot 'build'
New-Item -ItemType Directory -Force -Path $buildPath | Out-Null
function Invoke-SimTool([string]$Name, [string[]]$Arguments) {
    $executable = if ($SimulatorBin) { Join-Path $SimulatorBin ($Name + '.exe') } else { $Name }
    & $executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Name failed with exit code $LASTEXITCODE" }
}
Push-Location $buildPath
try {
    Invoke-SimTool 'vlib' @('work')
    foreach ($source in @('rtl/biss_emulator_pkg.vhd', 'rtl/biss_motion_generator.vhd',
                          'rtl/biss_frame_engine.vhd', 'rtl/biss_emulator_top.vhd',
                          'sim/tb_biss_frame_engine.vhd')) {
        Invoke-SimTool 'vcom' @('-2008', '-work', 'work', (Join-Path $sourceRoot $source))
    }
    $cases = @(
        @('-gG_SAFETY_MODE=false'),
        @('-gG_SAFETY_MODE=true', '-gG_SPW_ST_BITS=18', '-gG_SPW_MT_BITS=0'),
        @('-gG_SAFETY_MODE=true', '-gG_SPW_ST_BITS=1', '-gG_SPW_MT_BITS=0'),
        @('-gG_SAFETY_MODE=true', '-gG_SPW_ST_BITS=24', '-gG_SPW_MT_BITS=12'),
        @('-gG_SAFETY_MODE=true', '-gG_SPW_ST_BITS=32', '-gG_SPW_MT_BITS=8'),
        @('-gG_SAFETY_MODE=true', '-gG_SPW_ST_BITS=16', '-gG_SPW_MT_BITS=6')
    )
    foreach ($case in $cases) {
        Invoke-SimTool 'vsim' (@('-c', '-onfinish', 'exit', 'work.tb_biss_frame_engine') + $case +
            @('-do', ('do "' + (Join-Path $PSScriptRoot 'run.do').Replace('\', '/') + '"')))
    }
    $vsimExecutable = if ($SimulatorBin) { Join-Path $SimulatorBin 'vsim.exe' } else { 'vsim' }
    & $vsimExecutable -c -onfinish exit work.tb_biss_frame_engine -gG_SAFETY_MODE=true `
        -gG_SPW_ST_BITS=32 -gG_SPW_MT_BITS=12 `
        -do ('do "' + (Join-Path $PSScriptRoot 'run.do').Replace('\', '/') + '"') *> invalid-width.log
    if ($LASTEXITCODE -eq 0 -or -not (Select-String -Path invalid-width.log -Pattern 'SPW position must contain')) {
        throw 'Invalid SPW width was not rejected by the RTL assertion.'
    }
    Write-Output 'All six frame-engine configurations passed; invalid SPW width rejected.'
    $global:LASTEXITCODE = 0
} finally {
    Pop-Location
}
