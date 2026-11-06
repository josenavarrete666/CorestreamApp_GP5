from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import AliasChoices, BaseModel, Field


class UploaderResponse(BaseModel):
    id: UUID
    full_name: Optional[str] = None
    email: str

    model_config = {"from_attributes": True}


class DocumentResponse(BaseModel):
    id: UUID
    filename: str
    file_size: int
    mime_type: str
    doc_type: str
    epic_id: Optional[UUID] = None
    ticket_id: Optional[UUID] = None
    uploaded_by_id: Optional[UUID] = None
    uploaded_by: Optional[UploaderResponse] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class TranslateRequest(BaseModel):
    target_language: str = Field(..., max_length=10)  # código ISO 639-1: "en", "es", "fr", "de", "pt", "it", "zh", "ar"


class TranslateResponse(BaseModel):
    document_id: UUID
    original_filename: str
    target_language: str
    translated_text: str


class UploadUrlRequest(BaseModel):
    filename: str = Field(..., min_length=1, max_length=255)
    size: int = Field(..., ge=0)
    content_type: Optional[str] = Field(None, max_length=100)
    epic_id: Optional[UUID] = Field(None, validation_alias=AliasChoices("epic_id", "epicId"))
    ticket_id: Optional[UUID] = Field(None, validation_alias=AliasChoices("ticket_id", "ticketId"))
    doc_type: Optional[str] = Field(None, max_length=20, validation_alias=AliasChoices("doc_type", "docType"))


class UploadUrlResponse(BaseModel):
    upload_token: str
    url: str
    method: str
    headers: dict[str, str]
    expires_in: int


class ConfirmUploadRequest(BaseModel):
    upload_token: str = Field(..., max_length=4096)


class DownloadUrlResponse(BaseModel):
    url: str
    filename: str
    expires_in: int
