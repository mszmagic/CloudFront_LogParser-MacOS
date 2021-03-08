//
//  ViewController.swift
//  CloudFront-AccessLog-Parser
//
//  Created by Shunzhe Ma on R 3/03/08.
//

import Cocoa
import Gzip

class ViewController: NSViewController {
    
    @IBOutlet var tableView: NSTableView!
    
    var propertyNames: [String]?
    var entries = [[String: String]]()
    
    var processedFileNames = [String]()

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.headerView?.needsDisplay = true
        tableView.delegate = self
        tableView.dataSource = self
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    @IBAction func actionPickFiles(_ sender: Any?) {
        let filePicker = NSOpenPanel()
        filePicker.allowsMultipleSelection = true
        filePicker.canChooseDirectories = false
        if filePicker.runModal() == .OK {
            let selectedFilePaths = filePicker.urls
            processFiles(selectedFilePaths: selectedFilePaths)
        }
    }
    
    func processFiles(selectedFilePaths: [URL]) {
        for filePath in selectedFilePaths {
            guard !self.processedFileNames.contains(filePath.lastPathComponent) else { return }
            guard filePath.lastPathComponent.hasSuffix(".gz") else { return }
            self.processedFileNames.append(filePath.lastPathComponent)
            if let fileData = try? Data(contentsOf: filePath),
               let unzippedFileData = try? fileData.gunzipped(),
               let fileTextContent = String(data: unzippedFileData, encoding: .utf8) {
                let fileLines = fileTextContent.components(separatedBy: .newlines)
                for lineI in 0..<fileLines.count {
                    let lineContent = fileLines[lineI]
                    /* 1行目はバージョン番号をストアします */
                    if lineI == 0 {
                        continue
                    }
                    /* 2行目はプロパティ名をストアします */
                    else if lineI == 1 {
                        processPropertyNames(names: lineContent.components(separatedBy: .whitespaces))
                    }
                    /* 以降の行は訪問ログをストアします */
                    else {
                        let properties = lineContent.components(separatedBy: .whitespaces)
                        guard properties.count == self.propertyNames?.count else { continue }
                        var newEntryLine = [String: String]()
                        for propertyI in 0..<properties.count {
                            let entryName = self.propertyNames?[propertyI] ?? ""
                            let entryValue = properties[propertyI]
                            newEntryLine[entryName] = entryValue
                        }
                        self.entries.append(newEntryLine)
                        DispatchQueue.main.async {
                            self.tableView.reloadData()
                        }
                    }
                }
            }
        }
    }
    
    /*
     プロパティの名前を解析する
     */
    func processPropertyNames(names: [String]) {
        guard names.first?.trimmingCharacters(in: .whitespaces) == "#Fields:" else {
            print("Not a standard AWS CloudFront log format.")
            return
        }
        if let existingPropertyNames = self.propertyNames {
            /*
             このファイルが以前のファイルと同じ形式であるかどうかを確認してください。
             */
            guard (names.count - 1) == existingPropertyNames.count else {
                print("Files have different #Fields: header.")
                return
            }
        } else {
            /*
             これが最初に解析するファイルです。プロパティ名を記録してください
             */
            self.propertyNames = names.map({ name in
                return name.trimmingCharacters(in: .whitespaces)
            })
            self.propertyNames?.removeFirst()
            /* 新しいテーブル列の追加 */
            DispatchQueue.main.async {
                for columnName in (self.propertyNames ?? []) {
                    let newColumn = NSTableColumn()
                    newColumn.headerCell.title = columnName
                    newColumn.identifier = NSUserInterfaceItemIdentifier(rawValue: columnName)
                    self.tableView.addTableColumn(newColumn)
                    self.tableView.reloadData()
                }
            }
        }
    }
    
    /*
     データをCSVファイルに書き出す
     */
    
    @IBAction func actionGenerateCSVFile(_ sender: Any?) {
        saveCSVandOpen()
    }
    
    @IBAction func actionOpenAsCSVFile(_ sender: Any?) {
        saveCSVandOpen(toTempPath: true)
    }
    
    func saveCSVandOpen(toTempPath: Bool = false) {
        var csvString = ""
        /* まず最初に、全てのプロパティ名を保存します */
        guard let allPropertyNames = self.propertyNames?.joined(separator: ",") else { return }
        csvString.append(allPropertyNames + "\n")
        /* 各エントリーを追加します */
        for entry in self.entries {
            var entryValues = [String]()
            for propertyName in (self.propertyNames ?? []) {
                let entryValue = entry[propertyName] ?? "-"
                entryValues.append(entryValue)
            }
            csvString.append(entryValues.joined(separator: ",") + "\n")
        }
        /* データをファイルへ書き込みます */
        if toTempPath {
            let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory().appending("\(UUID().uuidString).csv"))
            try? csvString.write(to: tempDirectory, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(tempDirectory)
        } else {
            /* NSSavePanelを表示させ、ユーザーにファイルの保存場所を選択してもらう */
            let savePanel = NSSavePanel()
            savePanel.allowedFileTypes = ["csv"]
            savePanel.begin { response in
                if response == .OK,
                   let filePath = savePanel.url {
                    try? csvString.write(to: filePath, atomically: true, encoding: .utf8)
                    NSWorkspace.shared.open(filePath)
                }
            }
        }
    }


}

extension ViewController: NSTableViewDelegate, NSTableViewDataSource {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.entries.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let columnId = tableColumn?.identifier.rawValue ?? UUID().uuidString
        let view = NSTextField()
        view.isBezeled = false
        view.drawsBackground = false
        view.isEditable = false
        view.isSelectable = false
        view.stringValue = self.entries[row][columnId] ?? ""
        return view
    }
    
}
