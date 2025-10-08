# Test script to diagnose Excel generation issue
Write-Host "🧪 Testing Excel Generation in Container Environment" -ForegroundColor Cyan

# Check if libgdiplus is installed
Write-Host "`n1️⃣ Checking libgdiplus installation..." -ForegroundColor Yellow
$libCheck = bash -c "dpkg -l | grep libgdiplus"
if ($libCheck) {
    Write-Host "✅ libgdiplus is installed:" -ForegroundColor Green
    Write-Host $libCheck
} else {
    Write-Host "❌ libgdiplus is NOT installed" -ForegroundColor Red
}

# Check ImportExcel module
Write-Host "`n2️⃣ Checking ImportExcel module..." -ForegroundColor Yellow
$module = Get-Module -ListAvailable ImportExcel
if ($module) {
    Write-Host "✅ ImportExcel version: $($module.Version)" -ForegroundColor Green
} else {
    Write-Host "❌ ImportExcel module not found" -ForegroundColor Red
}

# Test basic Excel file creation
Write-Host "`n3️⃣ Testing basic Excel file creation..." -ForegroundColor Yellow
try {
    $testData = @(
        [PSCustomObject]@{ Name = "Test1"; Value = 100 }
        [PSCustomObject]@{ Name = "Test2"; Value = 200 }
    )
    
    $testFile = "/tmp/test-excel-$(Get-Date -Format 'yyyyMMdd-HHmmss').xlsx"
    Write-Host "Creating test file: $testFile" -ForegroundColor Cyan
    
    $testData | Export-Excel -Path $testFile -AutoSize -TableName "TestData" -WorksheetName "Test"
    
    if (Test-Path $testFile) {
        $fileSize = (Get-Item $testFile).Length
        Write-Host "✅ Excel file created successfully! Size: $fileSize bytes" -ForegroundColor Green
        Remove-Item $testFile -Force
    } else {
        Write-Host "❌ Excel file was not created" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Error creating Excel file:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
}

# Test with chart creation
Write-Host "`n4️⃣ Testing Excel with chart creation..." -ForegroundColor Yellow
try {
    $chartData = @(
        [PSCustomObject]@{ Category = "A"; Value = 10 }
        [PSCustomObject]@{ Category = "B"; Value = 20 }
        [PSCustomObject]@{ Category = "C"; Value = 15 }
    )
    
    $chartFile = "/tmp/test-chart-$(Get-Date -Format 'yyyyMMdd-HHmmss').xlsx"
    Write-Host "Creating test file with chart: $chartFile" -ForegroundColor Cyan
    
    $excel = $chartData | Export-Excel -Path $chartFile -AutoSize -TableName "ChartData" -WorksheetName "Chart" -PassThru
    
    # Try to add a chart
    $ws = $excel.Workbook.Worksheets["Chart"]
    $chart = $ws.Drawings.AddChart("TestChart", [OfficeOpenXml.Drawing.Chart.eChartType]::ColumnClustered)
    $chart.SetPosition(5, 0, 5, 0)
    $chart.SetSize(400, 300)
    $chart.Title.Text = "Test Chart"
    
    Close-ExcelPackage $excel
    
    if (Test-Path $chartFile) {
        $fileSize = (Get-Item $chartFile).Length
        Write-Host "✅ Excel file with chart created successfully! Size: $fileSize bytes" -ForegroundColor Green
        Remove-Item $chartFile -Force
    } else {
        Write-Host "❌ Excel file with chart was not created" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Error creating Excel file with chart:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
}

Write-Host "`n✅ Test completed!" -ForegroundColor Green
