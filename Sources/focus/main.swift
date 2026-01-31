import ArgumentParser
import FocusCore

@main
struct Focus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focus",
        abstract: "macOS Screen Time Tracker",
        version: "1.0.0",
        subcommands: [
            SummaryCommand.self,
            LogCommand.self,
            DeleteCommand.self,
            InstallCommand.self,
            UninstallCommand.self
        ],
        defaultSubcommand: SummaryCommand.self
    )
}
