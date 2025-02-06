# bmi_calculator

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
# Install required packages
!pip install PyPDF2 ipywidgets python-docx nltk beautifulsoup4 markdown

import os
from google.cloud import aiplatform
import PyPDF2
import json
from datetime import datetime
import io
import nltk
from nltk.tokenize import sent_tokenize
from nltk.corpus import stopwords
from bs4 import BeautifulSoup
import re
from docx import Document
import markdown
import ipywidgets as widgets
from IPython.display import display, HTML
from typing import List, Dict, Any
import logging

# Download required NLTK data
nltk.download('punkt')
nltk.download('stopwords')

class DocumentProcessor:
    """Enhanced document processing capabilities"""
    
    def __init__(self):
        self.supported_formats = {
            '.pdf': self._process_pdf,
            '.txt': self._process_text,
            '.docx': self._process_docx,
            '.md': self._process_markdown,
            '.html': self._process_html
        }

    def process_document(self, file_path: str) -> Dict[str, Any]:
        """Process document and return structured content"""
        file_ext = os.path.splitext(file_path)[1].lower()
        
        if file_ext not in self.supported_formats:
            raise ValueError(f"Unsupported file format: {file_ext}")
        
        try:
            content = self.supported_formats[file_ext](file_path)
            sections = self._split_into_sections(content)
            return {
                'full_text': content,
                'sections': sections,
                'summary': self._generate_summary(content),
                'keywords': self._extract_keywords(content)
            }
        except Exception as e:
            logging.error(f"Error processing document {file_path}: {str(e)}")
            raise

    def _process_pdf(self, file_path: str) -> str:
        with open(file_path, 'rb') as file:
            pdf_reader = PyPDF2.PdfReader(file)
            text = ""
            for page in pdf_reader.pages:
                text += page.extract_text() + "\n"
        return self._clean_text(text)

    def _process_text(self, file_path: str) -> str:
        with open(file_path, 'r', encoding='utf-8') as file:
            return self._clean_text(file.read())

    def _process_docx(self, file_path: str) -> str:
        doc = Document(file_path)
        return self._clean_text('\n'.join([paragraph.text for paragraph in doc.paragraphs]))

    def _process_markdown(self, file_path: str) -> str:
        with open(file_path, 'r', encoding='utf-8') as file:
            md_content = file.read()
            html_content = markdown.markdown(md_content)
            return self._clean_text(BeautifulSoup(html_content, 'html.parser').get_text())

    def _process_html(self, file_path: str) -> str:
        with open(file_path, 'r', encoding='utf-8') as file:
            return self._clean_text(BeautifulSoup(file.read(), 'html.parser').get_text())

    def _clean_text(self, text: str) -> str:
        """Clean and normalize text content"""
        # Remove extra whitespace
        text = re.sub(r'\s+', ' ', text)
        # Remove special characters
        text = re.sub(r'[^\w\s.,!?-]', '', text)
        return text.strip()

    def _split_into_sections(self, text: str) -> List[Dict[str, str]]:
        """Split text into meaningful sections"""
        sentences = sent_tokenize(text)
        sections = []
        current_section = []
        
        for sentence in sentences:
            current_section.append(sentence)
            if len(' '.join(current_section)) >= 1000:  # Approximate section size
                sections.append({
                    'content': ' '.join(current_section),
                    'length': len(current_section)
                })
                current_section = []
        
        if current_section:
            sections.append({
                'content': ' '.join(current_section),
                'length': len(current_section)
            })
        
        return sections

    def _extract_keywords(self, text: str) -> List[str]:
        """Extract key terms from text"""
        words = text.lower().split()
        stop_words = set(stopwords.words('english'))
        keywords = [word for word in words if word not in stop_words and len(word) > 3]
        return list(set(keywords))

    def _generate_summary(self, text: str) -> str:
        """Generate a brief summary of the text"""
        sentences = sent_tokenize(text)
        return ' '.join(sentences[:3])  # Simple summarization using first 3 sentences

class KnowledgeBaseSystem:
    def __init__(self, project_id='cloud-workspace-poc-51731', location='us-central1'):
        self.project_id = project_id
        self.location = location
        aiplatform.init(project=project_id, location=location)
        self.model = aiplatform.TextGenerationModel.from_pretrained("text-bison@001")
        self.knowledge_base = {}
        self.knowledge_base_path = 'knowledge_base.json'
        self.doc_processor = DocumentProcessor()
        self.load_knowledge_base()

    def load_knowledge_base(self):
        """Load existing knowledge base"""
        try:
            if os.path.exists(self.knowledge_base_path):
                with open(self.knowledge_base_path, 'r', encoding='utf-8') as f:
                    self.knowledge_base = json.load(f)
                print(f"Loaded {len(self.knowledge_base)} documents from knowledge base")
            else:
                print("No existing knowledge base found. Creating new one.")
        except Exception as e:
            logging.error(f"Error loading knowledge base: {str(e)}")
            self.knowledge_base = {}

    def save_knowledge_base(self):
        """Save knowledge base to file"""
        try:
            with open(self.knowledge_base_path, 'w', encoding='utf-8') as f:
                json.dump(self.knowledge_base, f, ensure_ascii=False, indent=2)
            print("Knowledge base saved successfully")
        except Exception as e:
            logging.error(f"Error saving knowledge base: {str(e)}")

    def add_document_to_knowledge_base(self, file_path: str):
        """Add a new document to the knowledge base"""
        try:
            doc_id = os.path.basename(file_path)
            
            # Process document
            doc_info = self.doc_processor.process_document(file_path)
            
            # Store document with metadata
            self.knowledge_base[doc_id] = {
                'content': doc_info['full_text'],
                'sections': doc_info['sections'],
                'summary': doc_info['summary'],
                'keywords': doc_info['keywords'],
                'added_date': datetime.now().isoformat(),
                'file_path': file_path
            }
            
            self.save_knowledge_base()
            print(f"Successfully added {doc_id} to knowledge base")
            
        except Exception as e:
            logging.error(f"Error adding document {file_path}: {str(e)}")

    def search_knowledge_base(self, query: str, max_relevant_chunks: int = 3) -> List[Dict[str, Any]]:
        """Enhanced search functionality"""
        try:
            query_keywords = set(self.doc_processor._extract_keywords(query))
            relevant_sections = []
            
            for doc_id, doc_info in self.knowledge_base.items():
                # Calculate relevance score for each section
                for section in doc_info['sections']:
                    section_keywords = set(self.doc_processor._extract_keywords(section['content']))
                    relevance_score = len(query_keywords.intersection(section_keywords))
                    
                    if relevance_score > 0:
                        relevant_sections.append({
                            'doc_id': doc_id,
                            'content': section['content'],
                            'score': relevance_score,
                            'summary': doc_info['summary']
                        })
            
            # Sort by relevance and take top chunks
            relevant_sections.sort(key=lambda x: x['score'], reverse=True)
            return relevant_sections[:max_relevant_chunks]
            
        except Exception as e:
            logging.error(f"Error searching knowledge base: {str(e)}")
            return []

    def generate_response(self, query: str, additional_context: str = "") -> str:
        """Generate enhanced response using Vertex AI"""
        try:
            relevant_sections = self.search_knowledge_base(query)
            
            if not relevant_sections:
                return "No relevant information found in the knowledge base. Please try rephrasing your query or upload relevant documentation."

            # Construct enhanced prompt with relevant information
            context = "\n\n".join([
                f"From document {section['doc_id']}:\n"
                f"Document Summary: {section['summary']}\n"
                f"Relevant Section: {section['content']}"
                for section in relevant_sections
            ])

            prompt = f"""
            User Query: {query}

            Additional Context (if provided): {additional_context}

            Relevant Information from Knowledge Base:
            {context}

            Please provide a comprehensive response following these guidelines:

            1. Answer Accuracy:
               - Use ONLY information from the provided documentation
               - If information is insufficient, clearly state what cannot be answered
               - Do not make assumptions or add information not present in the sources

            2. Response Structure:
               - Start with a direct answer to the query
               - Provide relevant details and context
               - Include step-by-step instructions if applicable
               - List any prerequisites or dependencies mentioned

            3. Source Attribution:
               - Reference specific documents for key information
               - Indicate which document contains which part of the answer

            4. Technical Details:
               - Include any specific technical parameters mentioned
               - Note any version requirements or compatibility issues
               - Highlight any warnings or important considerations

            5. Additional Considerations:
               - Mention any related topics that might be relevant
               - Note any limitations or edge cases
               - Suggest related queries if applicable

            Remember: Base your response ONLY on the provided documentation. If certain aspects of the query cannot be answered from the available information, explicitly state this limitation.
            """

            response = self.model.predict(
                prompt,
                temperature=0.3,
                max_output_tokens=1024,
                top_p=0.8,
                top_k=40
            )
            
            return response.text

        except Exception as e:
            logging.error(f"Error generating response: {str(e)}")
            return f"Error generating response: {str(e)}"

class KnowledgeBaseInterface:
    def __init__(self, kb_system):
        self.kb_system = kb_system
        self.setup_interface()

    def setup_interface(self):
        # Create enhanced widgets
        self.query_input = widgets.Textarea(
            placeholder='Enter your question here...',
            layout={'width': '800px', 'height': '100px'}
        )
        
        self.upload_button = widgets.Button(
            description='Upload New Document',
            layout={'width': 'auto'},
            style={'button_color': '#4CAF50'}
        )
        
        self.search_button = widgets.Button(
            description='Search',
            layout={'width': 'auto'},
            style={'button_color': '#2196F3'}
        )
        
        self.status_label = widgets.Label(value="")
        
        self.output_area = widgets.Output()
        
        # Set up callbacks
        self.upload_button.on_click(self.handle_upload)
        self.search_button.on_click(self.handle_search)
        
        # Create layout
        header = HTML("""
        <style>
        .custom-header {
            background-color: #f5f5f5;
            padding: 10px;
            border-radius: 5px;
            margin-bottom: 20px;
        }
        </style>
        <div class="custom-header">
            <h2>Knowledge Base Query System</h2>
            <p>Enter your query below or upload new documentation to the knowledge base.</p>
        </div>
        """)
        
        # Display interface
        display(header)
        display(self.query_input)
        display(widgets.HBox([self.search_button, self.upload_button]))
        display(self.status_label)
        display(self.output_area)

    def handle_upload(self, button):
        with self.output_area:
            self.output_area.clear_output()
            self.status_label.value = "Uploading document..."
            try:
                uploaded = files.upload()
                for filename, content in uploaded.items():
                    # Save temporarily
                    with open(filename, 'wb') as f:
                        f.write(content)
                    # Add to knowledge base
                    self.kb_system.add_document_to_knowledge_base(filename)
                    # Clean up
                    os.remove(filename)
                self.status_label.value = "Document(s) added to knowledge base successfully!"
            except Exception as e:
                self.status_label.value = f"Error uploading document: {str(e)}"

    def handle_search(self, button):
        with self.output_area:
            self.output_area.clear_output()
            query = self.query_input.value.strip()
            if query:
                self.status_label.value = "Searching and generating response..."
                response = self.kb_system.generate_response(query)
                print("\nQuery:", query)
                print("\nResponse:")
                print(response)
                self.status_label.value = "Response generated successfully!"
            else:
                self.status_label.value = "Please enter a query first."

# Usage Example
def launch_system():
    # Set up logging
    logging.basicConfig(level=logging.INFO)
    
    # Initialize system
    kb_system = KnowledgeBaseSystem()
    
    # Create documents folder if it doesn't exist
    documents_folder = "knowledge_base_docs"
    if not os.path.exists(documents_folder):
        os.makedirs(documents_folder)
    
    # Load any existing documents
    for filename in os.listdir(documents_folder):
        file_path = os.path.join(documents_folder, filename)
        if any(filename.endswith(ext) for ext in ['.pdf', '.txt', '.docx', '.md', '.html']):
            kb_system.add_document_to_knowledge_base(file_path)
    
    # Launch interface
    interface = KnowledgeBaseInterface(kb_system)
    return kb_system, interface

# Run the system
kb_system, interface = launch_system()