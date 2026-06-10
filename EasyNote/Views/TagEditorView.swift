import SwiftUI
import SwiftData

struct TagEditorView: View {
    @Environment(\.dismiss) private var dismiss
    
    // 两种初始化方式的支持
    @Binding var tags: [String]
    private var originalTags: [String] = []
    private var onSave: (([String]) -> Void)?
    
    @State private var newTag: String = ""
    @State private var editedTags: [String] = []
    
    // 初始化方式1：使用绑定
    init(tags: Binding<[String]>) {
        self._tags = tags
        self._editedTags = State(initialValue: tags.wrappedValue)
        self.onSave = nil
    }
    
    // 初始化方式2：使用数组和回调
    init(tags: [String], onSave: @escaping ([String]) -> Void) {
        self._tags = .constant([])
        self.originalTags = tags
        self._editedTags = State(initialValue: tags)
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 标签输入区域
                HStack {
                    TextField("新标签", text: $newTag)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                        .onSubmit {
                            addTag()
                        }
                    
                    Button(action: addTag) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                    .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                
                // 当前标签列表
                if editedTags.isEmpty {
                    VStack(spacing: 15) {
                        Spacer()
                        
                        Image(systemName: "tag")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        
                        Text("还没有标签")
                            .font(.title3)
                            .foregroundColor(.gray)
                        
                        Text("添加标签可以更好地组织和查找您的日记")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 10) {
                            ForEach(editedTags, id: \.self) { tag in
                                TagView(tag: tag) {
                                    // 删除标签
                                    if let index = editedTags.firstIndex(of: tag) {
                                        editedTags.remove(at: index)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .animation(.default, value: editedTags)
                    }
                }
                
                Spacer()
            }
            .padding(.top)
            .navigationTitle("编辑标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveChanges()
                    }
                }
            }
            .onAppear {
                // 初始化编辑标签
                if onSave != nil {
                    editedTags = originalTags
                } else {
                    editedTags = tags
                }
            }
        }
    }
    
    // 添加新标签
    private func addTag() {
        let trimmedTag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !trimmedTag.isEmpty && !editedTags.contains(trimmedTag) {
            withAnimation {
                editedTags.append(trimmedTag)
                newTag = ""
            }
        }
    }
    
    // 保存更改
    private func saveChanges() {
        if let saveCallback = onSave {
            // 使用回调方式
            saveCallback(editedTags)
        } else {
            // 使用绑定方式
            tags = editedTags
        }
        dismiss()
    }
}

// 标签视图组件
struct TagView: View {
    let tag: String
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Text(tag)
                .font(.subheadline)
                .lineLimit(1)
            
            Spacer()
            
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
                    .font(.footnote)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.green.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    TagEditorView(tags: .constant(["家庭", "工作", "生活", "旅行"]))
} 