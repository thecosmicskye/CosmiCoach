import SwiftUI

struct OperationStatusView: View {
    let statusMessage: OperationStatusMessage
    
    var body: some View {
        HStack {
            Spacer()
            
            HStack(spacing: 8) {
                if statusMessage.status == .inProgress {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: statusMessage.status.icon)
                        .foregroundColor(statusMessage.status == .success ? .green : .red)
                }
                
                Text(statusMessage.displayText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            Spacer()
        }
        .padding(.vertical, 4)
        .id("status-view-\(statusMessage.id)")
    }
}

#Preview {
    VStack {
        OperationStatusView(statusMessage: OperationStatusMessage(
            operationType: .addReminder,
            status: .inProgress
        ))
        
        OperationStatusView(statusMessage: OperationStatusMessage(
            operationType: .addReminder,
            status: .success,
            count: 1
        ))
        
        OperationStatusView(statusMessage: OperationStatusMessage(
            operationType: .addReminder,
            status: .success,
            count: 3
        ))
        
        OperationStatusView(statusMessage: OperationStatusMessage(
            operationType: .deleteCalendarEvent,
            status: .success,
            count: 2
        ))
        
        OperationStatusView(statusMessage: OperationStatusMessage(
            operationType: .addReminder,
            status: .failure,
            details: "Permission denied"
        ))
    }
    .padding()
}
